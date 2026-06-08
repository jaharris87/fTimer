module example_instrumentation
   implicit none
   private

   logical, parameter, public :: timing_enabled = .false.
   integer, parameter, public :: timing_success = 0

   public :: timing_init
   public :: timing_finalize
   public :: timing_start
   public :: timing_stop
   public :: timing_get_entry_count
   public :: timing_print_summary

contains

   subroutine timing_init(ierr)
      integer, intent(out), optional :: ierr

      ! Disabled builds still return success so instrumentation calls can remain
      ! in application code without creating timing data.
      if (present(ierr)) ierr = timing_success
   end subroutine timing_init

   subroutine timing_finalize(ierr)
      integer, intent(out), optional :: ierr

      if (present(ierr)) ierr = timing_success
   end subroutine timing_finalize

   subroutine timing_start(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      if (present(ierr)) ierr = timing_success
   end subroutine timing_start

   subroutine timing_stop(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      if (present(ierr)) ierr = timing_success
   end subroutine timing_stop

   subroutine timing_get_entry_count(num_entries, ierr)
      integer, intent(out) :: num_entries
      integer, intent(out), optional :: ierr

      num_entries = 0
      if (present(ierr)) ierr = timing_success
   end subroutine timing_get_entry_count

   subroutine timing_print_summary(ierr)
      integer, intent(out), optional :: ierr

      if (present(ierr)) ierr = timing_success
   end subroutine timing_print_summary

end module example_instrumentation
