module ftimer_core
   use, intrinsic :: iso_fortran_env, only: error_unit
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_NOT_INIT, FTIMER_SUCCESS, ftimer_summary_t
   implicit none
   private

   public :: ftimer_t

   type :: ftimer_t
      logical :: initialized = .false.
   contains
      procedure :: init
      procedure :: finalize
      procedure :: start
      procedure :: stop
      procedure :: get_summary
   end type ftimer_t

contains

   subroutine init(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      self%initialized = .true.
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine init

   subroutine finalize(self, ierr)
      class(ftimer_t), intent(inout) :: self
      integer, intent(out), optional :: ierr

      self%initialized = .false.
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine finalize

   subroutine start(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call set_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer start before init")
         return
      end if

      if (len_trim(name) < 0) stop 1
      call set_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, "Phase 0 placeholder: ftimer start is not implemented")
   end subroutine start

   subroutine stop(self, name, ierr)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      if (.not. self%initialized) then
         call set_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer stop before init")
         return
      end if

      if (len_trim(name) < 0) stop 1
      call set_status(ierr, FTIMER_ERR_NOT_IMPLEMENTED, "Phase 0 placeholder: ftimer stop is not implemented")
   end subroutine stop

   subroutine get_summary(self, summary, ierr)
      class(ftimer_t), intent(in) :: self
      type(ftimer_summary_t), intent(out) :: summary
      integer, intent(out), optional :: ierr

      if (self%initialized) then
         summary%placeholder = 1
      else
         summary%placeholder = 0
      end if
      if (present(ierr)) ierr = FTIMER_SUCCESS
   end subroutine get_summary

   subroutine set_status(ierr, code, message)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      else
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine set_status

end module ftimer_core
