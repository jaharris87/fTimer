program ftimer_installed_consumer
  use ftimer, only : ftimer_init, ftimer_finalize
  implicit none
  integer :: ierr

  call ftimer_init(ierr=ierr)
  if (ierr /= 0) error stop 1

  call ftimer_finalize(ierr=ierr)
  if (ierr /= 0) error stop 2
end program ftimer_installed_consumer
