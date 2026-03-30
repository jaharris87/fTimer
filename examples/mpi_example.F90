program mpi_example
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_mpi_summary, ftimer_print_mpi_summary, &
                     ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_mpi_summary_t
   use mpi
   implicit none
   integer :: ierr
   integer :: i
   integer :: nprocs
   integer :: rank
   real :: accumulator
   type(ftimer_mpi_summary_t) :: summary

   call MPI_Init(ierr)
   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)

   call ftimer_init(comm=MPI_COMM_WORLD, ierr=ierr)
   call ftimer_start("rank_work", ierr=ierr)

   accumulator = 0.0
   do i = 1, (rank + 1)*150000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop("rank_work", ierr=ierr)
   call ftimer_mpi_summary(summary, ierr=ierr)

   if (rank == 0 .and. summary%num_entries > 0) then
      print '(a,i0)', "MPI ranks: ", nprocs
      print '(a,f12.6)', "Average inclusive time (s): ", summary%entries(1)%avg_inclusive_time
      print '(a,f12.6)', "Cross-rank max time (s): ", summary%entries(1)%max_inclusive_time
   end if
   call ftimer_print_mpi_summary(ierr=ierr)

   call ftimer_finalize(ierr=ierr)
   call MPI_Finalize(ierr)
   if (accumulator < 0.0) print *, accumulator
end program mpi_example
