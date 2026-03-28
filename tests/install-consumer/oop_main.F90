program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_t
   implicit none
   type(ftimer_t) :: timer
   integer :: ierr

   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 2
end program ftimer_installed_oop_consumer
