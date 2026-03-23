module ftimer_types
   implicit none
   private

   integer, parameter, public :: FTIMER_SUCCESS = 0
   integer, parameter, public :: FTIMER_ERR_NOT_INIT = 1
   integer, parameter, public :: FTIMER_ERR_NOT_IMPLEMENTED = 2
   integer, parameter, public :: wp = selected_real_kind(15, 307)

   type, public :: ftimer_summary_t
      integer :: placeholder = 0
   end type ftimer_summary_t

end module ftimer_types
