module ftimer_mpi
   implicit none
   private

   public :: ftimer_mpi_enabled

contains

   logical function ftimer_mpi_enabled()
      ftimer_mpi_enabled = .false.
   end function ftimer_mpi_enabled

end module ftimer_mpi
