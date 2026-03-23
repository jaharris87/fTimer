program test_phase0_smoke
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   use ftimer_mpi, only: ftimer_mpi_enabled
   use ftimer_types, only: FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_NOT_INIT, FTIMER_SUCCESS
   implicit none
   integer :: ierr

   call ftimer_start("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 1

   call ftimer_stop("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 2

   call ftimer_init(ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call ftimer_start("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 4

   call ftimer_stop("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_IMPLEMENTED) error stop 5

   call ftimer_finalize(ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6

#ifdef FTIMER_USE_MPI
   if (.not. ftimer_mpi_enabled()) error stop 7
#else
   if (ftimer_mpi_enabled()) error stop 8
#endif

   print *, "ftimer phase0 smoke ok"
end program test_phase0_smoke
