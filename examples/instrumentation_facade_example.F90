program instrumentation_facade_example
   use example_instrumentation, only: timing_enabled, timing_finalize, &
                                      timing_get_entry_count, timing_init, &
                                      timing_print_summary, timing_start, &
                                      timing_stop, timing_success
   implicit none
   integer :: entry_count
   integer :: ierr
   integer :: i
   real :: accumulator

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

   if (accumulator < 0.0) print *, accumulator
end program instrumentation_facade_example
