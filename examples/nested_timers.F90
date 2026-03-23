program nested_timers
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   implicit none

   call ftimer_init()
   call ftimer_start("outer")
   call ftimer_start("inner")
   call ftimer_stop("inner")
   call ftimer_stop("outer")
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: nested_timers"
end program nested_timers
