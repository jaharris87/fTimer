module ftimer_core
   use ftimer_types, only: ftimer_summary_t
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

   subroutine init(self)
      class(ftimer_t), intent(inout) :: self

      self%initialized = .true.
   end subroutine init

   subroutine finalize(self)
      class(ftimer_t), intent(inout) :: self

      self%initialized = .false.
   end subroutine finalize

   subroutine start(self, name)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name

      if (.not. self%initialized) return
      if (len_trim(name) < 0) stop 1
   end subroutine start

   subroutine stop(self, name)
      class(ftimer_t), intent(inout) :: self
      character(len=*), intent(in) :: name

      if (.not. self%initialized) return
      if (len_trim(name) < 0) stop 1
   end subroutine stop

   subroutine get_summary(self, summary)
      class(ftimer_t), intent(in) :: self
      type(ftimer_summary_t), intent(out) :: summary

      if (self%initialized) then
         summary%placeholder = 1
      else
         summary%placeholder = 0
      end if
   end subroutine get_summary

end module ftimer_core
