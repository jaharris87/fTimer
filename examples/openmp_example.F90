program openmp_example
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t
   use omp_lib, only: omp_get_num_threads, omp_get_thread_num, omp_set_dynamic
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_COMM_WORLD, MPI_Finalize, MPI_Init, MPI_SUCCESS
#endif
   implicit none
   integer, parameter :: NOOP_IERR_SENTINEL = -100
   integer :: i
   integer :: ierr
   integer :: local_ierr
   integer :: nthreads
   integer :: thread_num
   integer :: worker_calls
   integer :: worker_ierr_failures
   real :: accumulator
   logical :: thread_seen(2)
   type(ftimer_summary_t) :: summary

   call omp_set_dynamic(.false.)

   nthreads = 1
   accumulator = 0.0
   thread_seen = .false.
   worker_calls = 0
   worker_ierr_failures = 0

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Init failed"

   call ftimer_init(comm=MPI_COMM_WORLD, ierr=ierr)
#else
   call ftimer_init(ierr=ierr)
#endif
   if (ierr /= 0) error stop "ftimer_init failed"

   ! Supported pattern: time the parallel region as a whole by starting and
   ! stopping outside the !$omp parallel block. For asynchronous accelerator
   ! work, callers must synchronize device completion before stopping a timer.
   call ftimer_start("parallel_region", ierr=ierr)
   if (ierr /= 0) error stop "ftimer_start failed"
!$omp parallel num_threads(2) default(none) shared(accumulator, nthreads, thread_seen) &
!$omp& private(i, local_ierr, thread_num) reduction(+:worker_calls, worker_ierr_failures)
   thread_num = omp_get_thread_num()
   if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

   do i = 1, 150000
!$omp atomic update
      accumulator = accumulator + real(i)
   end do
!$omp master
   nthreads = omp_get_num_threads()
!$omp end master

   ! Misleading anti-pattern: placing ftimer_start/ftimer_stop inside this
   ! parallel region does not collect per-thread timings. Worker-thread calls
   ! are silent no-ops under the supported FTIMER_USE_OPENMP contract.
   if (thread_num /= 0) then
      local_ierr = NOOP_IERR_SENTINEL
      call ftimer_start("worker_only", ierr=local_ierr)
      if (local_ierr /= NOOP_IERR_SENTINEL) worker_ierr_failures = worker_ierr_failures + 1

      local_ierr = NOOP_IERR_SENTINEL
      call ftimer_stop("worker_only", ierr=local_ierr)
      if (local_ierr /= NOOP_IERR_SENTINEL) worker_ierr_failures = worker_ierr_failures + 1

      worker_calls = worker_calls + 1
   end if
!$omp end parallel
   call ftimer_stop("parallel_region", ierr=ierr)
   if (ierr /= 0) error stop "ftimer_stop failed"

   call ftimer_get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop "ftimer_get_summary failed"
   if (.not. thread_seen(1)) error stop "OpenMP master thread was not observed"
   if (.not. thread_seen(2)) error stop "OpenMP worker thread was not observed"
   if (nthreads < 2) error stop "OpenMP example did not run with at least two threads"
   if (worker_calls < 1) error stop "OpenMP worker no-op path was not exercised"
   if (worker_ierr_failures /= 0) error stop "OpenMP worker no-op path changed ierr"
   if (summary%num_entries /= 1) error stop "OpenMP example expected exactly one recorded timer"
   if (trim(summary%entries(1)%name) /= "parallel_region") error stop "OpenMP example recorded the wrong timer"
   if (summary%entries(1)%call_count /= 1) error stop "OpenMP example expected one timer call"

   print '(a)', "fTimer OpenMP support is limited to master-thread-only region bracketing."
   print '(a)', "This example measures one parallel region wall-clock interval,"
   print '(a)', "not per-thread timings."
   print '(a,i0)', "OpenMP threads observed: ", nthreads
   print '(a,i0)', "Recorded timers: ", summary%num_entries
   call ftimer_print_summary(ierr=ierr)
   if (ierr /= 0) error stop "ftimer_print_summary failed"
   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop "ftimer_finalize failed"
#ifdef FTIMER_USE_MPI
   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop "MPI_Finalize failed"
#endif
   if (accumulator < 0.0) print *, accumulator
end program openmp_example
