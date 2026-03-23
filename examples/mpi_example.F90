program mpi_example
   use ftimer, only: ftimer_finalize, ftimer_init
   implicit none

   call ftimer_init()
   call ftimer_finalize()

   print *, "fTimer Phase 0 placeholder example: mpi_example"
end program mpi_example
