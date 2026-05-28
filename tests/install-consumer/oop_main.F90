program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_guard_t, ftimer_t
   implicit none
   type(ftimer_t), target :: timer
   integer :: ierr

   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1

   block
      type(ftimer_guard_t) :: guard

      call timer%scope(guard, "oop-consumer", ierr=ierr)
      if (ierr /= 0) error stop 3
   end block

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 2
end program ftimer_installed_oop_consumer
