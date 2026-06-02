program test_phase0_smoke
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   use ftimer_mpi, only: ftimer_mpi_enabled
   use ftimer_types, only: FTIMER_ERR_NOT_INIT, FTIMER_SUCCESS
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
   implicit none
   integer :: ierr

   call ftimer_start("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 1

   call ftimer_stop("smoke", ierr)
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 2

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= 0) error stop 9
#endif

   call ftimer_init(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call ftimer_start("smoke", ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 4

   call ftimer_stop("smoke", ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 5

   call ftimer_finalize(ierr)
   if (ierr /= FTIMER_SUCCESS) error stop 6

#ifdef FTIMER_USE_MPI
   call MPI_Finalize(ierr)
   if (ierr /= 0) error stop 10
#endif

#ifdef FTIMER_USE_MPI
   if (.not. ftimer_mpi_enabled()) error stop 7
#else
   if (ftimer_mpi_enabled()) error stop 8
#endif

   print *, "ftimer smoke ok"
end program test_phase0_smoke
