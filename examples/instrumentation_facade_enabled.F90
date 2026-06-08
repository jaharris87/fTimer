module example_instrumentation
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: FTIMER_SUCCESS, ftimer_summary_t
   implicit none
   private

   logical, parameter, public :: timing_enabled = .true.
   integer, parameter, public :: timing_success = FTIMER_SUCCESS

   public :: timing_init
   public :: timing_finalize
   public :: timing_start
   public :: timing_stop
   public :: timing_get_entry_count
   public :: timing_print_summary

contains

   subroutine timing_init(ierr)
      integer, intent(out), optional :: ierr

      ! Keep facade status handling identical to fTimer so application code has
      ! one error path whether instrumentation is enabled or disabled.
      call ftimer_init(ierr=ierr)
   end subroutine timing_init

   subroutine timing_finalize(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_finalize(ierr=ierr)
   end subroutine timing_finalize

   subroutine timing_start(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_start(name, ierr=ierr)
   end subroutine timing_start

   subroutine timing_stop(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_stop(name, ierr=ierr)
   end subroutine timing_stop

   subroutine timing_get_entry_count(num_entries, ierr)
      integer, intent(out) :: num_entries
      integer, intent(out), optional :: ierr
      integer :: status
      type(ftimer_summary_t) :: summary

      num_entries = 0
      call ftimer_get_summary(summary, ierr=status)
      if (status == FTIMER_SUCCESS) num_entries = summary%num_entries
      if (present(ierr)) ierr = status
   end subroutine timing_get_entry_count

   subroutine timing_print_summary(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_print_summary(ierr=ierr)
   end subroutine timing_print_summary

end module example_instrumentation
