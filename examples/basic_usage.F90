program basic_usage
   use ftimer, only: ftimer_finalize, ftimer_init
   implicit none

   call ftimer_init()
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: basic_usage"
end program basic_usage
