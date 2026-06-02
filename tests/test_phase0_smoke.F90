program test_phase0_smoke
   use, intrinsic :: iso_fortran_env, only: error_unit
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   use ftimer_mpi, only: ftimer_mpi_enabled
   use ftimer_types, only: FTIMER_ERR_NOT_INIT, FTIMER_SUCCESS
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Finalize, MPI_Init
#endif
   implicit none
   integer :: ierr

   call ftimer_start("smoke", ierr)
   call phase0_mark("after pre-init start")
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 1

   call ftimer_stop("smoke", ierr)
   call phase0_mark("after pre-init stop")
   if (ierr /= FTIMER_ERR_NOT_INIT) error stop 2

#ifdef FTIMER_USE_MPI
   call MPI_Init(ierr)
   if (ierr /= 0) error stop 9
#endif

   call ftimer_init(ierr=ierr)
   call phase0_mark("after init")
   if (ierr /= FTIMER_SUCCESS) error stop 3

   call ftimer_start("smoke", ierr)
   call phase0_mark("after start")
   if (ierr /= FTIMER_SUCCESS) error stop 4

   call ftimer_stop("smoke", ierr)
   call phase0_mark("after stop")
   if (ierr /= FTIMER_SUCCESS) error stop 5

   call ftimer_finalize(ierr)
   call phase0_mark("after finalize")
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

contains

   subroutine phase0_mark(message)
      character(len=*), intent(in) :: message

      write (error_unit, '(a)') "phase0: "//message
      flush (error_unit)
   end subroutine phase0_mark
end program test_phase0_smoke
