program basic_usage
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t
   implicit none
   integer :: i
   real :: accumulator
   type(ftimer_summary_t) :: summary

   call ftimer_init()
   call ftimer_start("work")

   accumulator = 0.0
   do i = 1, 200000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop("work")
   call ftimer_get_summary(summary)

   print '(a,i0)', "Recorded timers: ", summary%num_entries
   call ftimer_print_summary()
   call ftimer_finalize()
   if (accumulator < 0.0) print *, accumulator
end program basic_usage
