program nested_timers
   use ftimer, only: ftimer_finalize, ftimer_init
   implicit none

   call ftimer_init()
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: nested_timers"
end program nested_timers
