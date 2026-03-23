module ftimer
   use ftimer_core, only: ftimer_t
   implicit none
   private

   public :: ftimer_init
   public :: ftimer_finalize
   public :: ftimer_start
   public :: ftimer_stop
   public :: ftimer_default_instance

   type(ftimer_t), save :: ftimer_default_instance

contains

   subroutine ftimer_init(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%init(ierr)
   end subroutine ftimer_init

   subroutine ftimer_finalize(ierr)
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%finalize(ierr)
   end subroutine ftimer_finalize

   subroutine ftimer_start(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%start(name, ierr)
   end subroutine ftimer_start

   subroutine ftimer_stop(name, ierr)
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: ierr

      call ftimer_default_instance%stop(name, ierr)
   end subroutine ftimer_stop

end module ftimer
