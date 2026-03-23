program basic_usage
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   implicit none

   call ftimer_init()
   call ftimer_start("phase0")
   call ftimer_stop("phase0")
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: basic_usage"
end program basic_usage
