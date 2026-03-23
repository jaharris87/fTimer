module ftimer_mpi
   implicit none
   private

   public :: ftimer_mpi_enabled

contains

   logical function ftimer_mpi_enabled()
#ifdef FTIMER_USE_MPI
      ftimer_mpi_enabled = .true.
#else
      ftimer_mpi_enabled = .false.
#endif
   end function ftimer_mpi_enabled

end module ftimer_mpi
