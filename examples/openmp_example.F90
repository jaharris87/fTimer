program openmp_example
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t
   use omp_lib, only: omp_get_num_threads
   implicit none
   integer :: i
   integer :: nthreads
   real :: accumulator
   type(ftimer_summary_t) :: summary

   nthreads = 1
   accumulator = 0.0

   call ftimer_init()

   ! Supported pattern: time the parallel region as a whole by starting and
   ! stopping outside the !$omp parallel block.
   call ftimer_start("parallel_region")
!$omp parallel default(none) shared(accumulator, nthreads) private(i)
   do i = 1, 150000
!$omp atomic update
      accumulator = accumulator + real(i)
   end do
!$omp single
   nthreads = omp_get_num_threads()
!$omp end single

   ! Misleading anti-pattern: placing ftimer_start/ftimer_stop inside this
   ! parallel region does not collect per-thread timings. Worker-thread calls
   ! are silent no-ops under the supported FTIMER_USE_OPENMP contract.
!$omp end parallel
   call ftimer_stop("parallel_region")

   call ftimer_get_summary(summary)
   print '(a,i0)', "OpenMP threads observed: ", nthreads
   print '(a,i0)', "Recorded timers: ", summary%num_entries
   call ftimer_print_summary()
   call ftimer_finalize()
   if (accumulator < 0.0) print *, accumulator
end program openmp_example
