program ftimer_installed_mpi_consumer
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_mpi_summary, ftimer_write_mpi_summary, &
                     ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_mpi_summary_t, wp
   use mpi
   implicit none
   integer :: ierr
   integer :: i
   integer :: rank
   real :: accumulator
   type(ftimer_mpi_summary_t) :: summary

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2

   call ftimer_init(comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= 0) error stop 3

   call ftimer_start("consumer_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 4

   accumulator = 0.0
   do i = 1, (rank + 1)*100000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop("consumer_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 5

   call ftimer_mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 6
   if (summary%num_ranks /= 2) error stop 7
   if (summary%num_entries /= 1) error stop 8
   if (trim(summary%entries(1)%name) /= "consumer_mpi_work") error stop 9
   if (summary%entries(1)%min_inclusive_time < 0.0_wp) error stop 10
   if (summary%entries(1)%max_inclusive_time < summary%entries(1)%min_inclusive_time) error stop 11
   if (summary%entries(1)%avg_inclusive_time < summary%entries(1)%min_inclusive_time) error stop 12
   if (summary%entries(1)%avg_call_count < 1.0_wp) error stop 13

   call ftimer_write_mpi_summary("consumer_mpi_summary.txt", ierr=ierr)
   if (ierr /= 0) error stop 14

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 15

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 16

   if (accumulator < 0.0) print *, accumulator
end program ftimer_installed_mpi_consumer
