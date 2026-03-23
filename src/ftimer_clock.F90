module ftimer_clock
   use ftimer_types, only: wp
   implicit none
   private

   public :: ftimer_default_clock

contains

   function ftimer_default_clock() result(t)
      real(wp) :: t
      integer :: count
      integer :: rate

      call system_clock(count, rate)
      if (rate > 0) then
         t = real(count, wp)/real(rate, wp)
      else
         t = 0.0_wp
      end if
   end function ftimer_default_clock

end module ftimer_clock
