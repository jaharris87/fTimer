program test_phase0_smoke
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   implicit none

   call ftimer_init()
   call ftimer_start("smoke")
   call ftimer_stop("smoke")
   call ftimer_finalize()

   print *, "ftimer phase0 smoke ok"
end program test_phase0_smoke
