program instrumentation_facade_example
   use example_instrumentation, only: timing_enabled, timing_finalize, &
                                      timing_get_entry_count, timing_init, &
                                      timing_print_summary, timing_start, &
                                      timing_stop, timing_success
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
   implicit none
   integer :: entry_count
   integer :: ierr
   integer :: i
   real :: accumulator

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= 0) error stop 9
#endif

   ! Applications can call a project facade instead of fTimer directly, then
   ! swap enabled/disabled instrumentation modules at build time.
   call timing_init(ierr=ierr)
   if (ierr /= timing_success) error stop 1

   call timing_start("work", ierr=ierr)
   if (ierr /= timing_success) error stop 2

   accumulator = 0.0
   do i = 1, 200000
      accumulator = accumulator + real(i)
   end do

   call timing_stop("work", ierr=ierr)
   if (ierr /= timing_success) error stop 3

   call timing_get_entry_count(entry_count, ierr=ierr)
   if (ierr /= timing_success) error stop 4

   if (timing_enabled) then
      if (entry_count /= 1) error stop 5
      call timing_print_summary(ierr=ierr)
      if (ierr /= timing_success) error stop 6
   else
      if (entry_count /= 0) error stop 7
      print '(a)', "Instrumentation disabled: timing calls were no-ops."
   end if

   call timing_finalize(ierr=ierr)
   if (ierr /= timing_success) error stop 8

#ifdef FTIMER_USE_MPI
   call MPI_Finalize(ierr)
   if (ierr /= 0) error stop 10
#endif

   if (accumulator < 0.0) print *, accumulator
end program instrumentation_facade_example
