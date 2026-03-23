program mpi_example
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_start, ftimer_stop
   implicit none

   call ftimer_init()
   call ftimer_start("mpi_phase0")
   call ftimer_stop("mpi_phase0")
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: mpi_example"
end program mpi_example
