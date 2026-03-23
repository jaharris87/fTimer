module ftimer_types
   implicit none
   private

   integer, parameter, public :: wp = selected_real_kind(15, 307)

   type, public :: ftimer_summary_t
      integer :: placeholder = 0
   end type ftimer_summary_t

end module ftimer_types
