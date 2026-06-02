program ftimer_installed_mpi_openmp_consumer
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_mpi_summary, ftimer_mpi_union_summary, &
                     ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_mpi_summary_t, ftimer_mpi_union_summary_t, wp
   use mpi_f08
   use omp_lib, only: omp_get_num_threads, omp_get_thread_num, omp_set_dynamic
   implicit none
   integer, parameter :: NOOP_IERR_SENTINEL = -100
   integer :: i
   integer :: ierr
   integer :: local_ierr
   integer :: nthreads
   integer :: rank
   integer :: thread_num
   integer :: worker_calls
   integer :: worker_ierr_failures
   real :: accumulator
   logical :: thread_seen(2)
   type(ftimer_mpi_summary_t) :: summary
   type(ftimer_mpi_union_summary_t) :: union_summary

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2

   call omp_set_dynamic(.false.)

   nthreads = 1
   accumulator = 0.0
   thread_seen = .false.
   worker_calls = 0
   worker_ierr_failures = 0

   call ftimer_init(comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= 0) error stop 3

   call ftimer_start("consumer_mpi_openmp_region", ierr=ierr)
   if (ierr /= 0) error stop 4

!$omp parallel num_threads(2) default(none) &
!$omp& shared(accumulator, nthreads, rank, thread_seen) &
!$omp& private(i, local_ierr, thread_num) &
!$omp& reduction(+:worker_calls, worker_ierr_failures)
   thread_num = omp_get_thread_num()
   if (thread_num + 1 <= size(thread_seen)) thread_seen(thread_num + 1) = .true.

   do i = 1, (rank + 1)*50000
!$omp atomic update
      accumulator = accumulator + real(i)
   end do

!$omp master
   nthreads = omp_get_num_threads()
!$omp end master

   if (thread_num /= 0) then
      local_ierr = NOOP_IERR_SENTINEL
      call ftimer_start("consumer_worker_only", ierr=local_ierr)
      if (local_ierr /= NOOP_IERR_SENTINEL) worker_ierr_failures = worker_ierr_failures + 1

      local_ierr = NOOP_IERR_SENTINEL
      call ftimer_stop("consumer_worker_only", ierr=local_ierr)
      if (local_ierr /= NOOP_IERR_SENTINEL) worker_ierr_failures = worker_ierr_failures + 1

      worker_calls = worker_calls + 1
   end if
!$omp end parallel

   call ftimer_stop("consumer_mpi_openmp_region", ierr=ierr)
   if (ierr /= 0) error stop 5

   if (.not. thread_seen(1)) error stop 6
   if (.not. thread_seen(2)) error stop 7
   if (nthreads < 2) error stop 8
   if (worker_calls < 1) error stop 9
   if (worker_ierr_failures /= 0) error stop 10

   call ftimer_mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 11
   if (summary%num_ranks /= 2) error stop 12
   if (summary%num_entries /= 1) error stop 13
   if (trim(summary%entries(1)%name) /= "consumer_mpi_openmp_region") error stop 14
   if (summary%entries(1)%min_inclusive_time < 0.0_wp) error stop 15
   if (summary%entries(1)%max_inclusive_time < summary%entries(1)%min_inclusive_time) error stop 16
   if (summary%entries(1)%avg_call_count < 1.0_wp) error stop 17
   if (kind(summary%entries(1)%min_call_count) /= int64) error stop 18
   if (kind(summary%entries(1)%max_call_count) /= int64) error stop 19

   call ftimer_mpi_union_summary(union_summary, ierr=ierr)
   if (ierr /= 0) error stop 20
   if (union_summary%num_ranks /= 2) error stop 21
   if (union_summary%num_entries /= 1) error stop 22
   if (trim(union_summary%entries(1)%name) /= "consumer_mpi_openmp_region") error stop 23
   if (union_summary%entries(1)%participating_rank_count /= 2) error stop 24
   if (union_summary%entries(1)%avg_call_count < 1.0_wp) error stop 25

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 26

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 27

   if (accumulator < 0.0) print *, accumulator
end program ftimer_installed_mpi_openmp_consumer
