module ftimer_summary
   use ftimer_types, only: ftimer_summary_t
   implicit none
   private

   public :: ftimer_summary_status

contains

   function ftimer_summary_status(summary) result(status)
      type(ftimer_summary_t), intent(in) :: summary
      integer :: status

      status = summary%placeholder
   end function ftimer_summary_status

end module ftimer_summary
