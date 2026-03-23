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

   subroutine ftimer_init()
      call ftimer_default_instance%init()
   end subroutine ftimer_init

   subroutine ftimer_finalize()
      call ftimer_default_instance%finalize()
   end subroutine ftimer_finalize

   subroutine ftimer_start(name)
      character(len=*), intent(in) :: name

      call ftimer_default_instance%start(name)
   end subroutine ftimer_start

   subroutine ftimer_stop(name)
      character(len=*), intent(in) :: name

      call ftimer_default_instance%stop(name)
   end subroutine ftimer_stop

end module ftimer
