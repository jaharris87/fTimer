program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_guard_t, ftimer_scope, ftimer_t
   implicit none
   type(ftimer_t), target :: timer
   type(ftimer_t), pointer :: timer_ptr
   integer :: ierr

   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1
   timer_ptr => timer

   block
      type(ftimer_guard_t) :: guard

      call ftimer_scope(timer_ptr, guard, "oop-consumer", ierr=ierr)
      if (ierr /= 0) error stop 3
   end block

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 2
end program ftimer_installed_oop_consumer
