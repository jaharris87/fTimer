program ftimer_installed_mpi_consumer
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_mpi_summary, ftimer_mpi_union_summary, &
                     ftimer_write_mpi_summary, ftimer_write_mpi_union_summary, &
                     ftimer_write_mpi_union_summary_csv, ftimer_start, ftimer_stop
   use ftimer_core, only: ftimer_t
   use ftimer_types, only: ftimer_mpi_summary_t, ftimer_mpi_union_summary_t, wp
   use mpi_f08
   implicit none
   integer :: ierr
   integer :: i
   integer :: rank
   character(len=64) :: summary_file
   character(len=64) :: union_summary_file
   character(len=64) :: union_summary_csv_file
   real :: accumulator
   type(ftimer_t) :: oop_timer
   type(MPI_Comm) :: subcomm
   type(ftimer_mpi_summary_t) :: summary
   type(ftimer_mpi_summary_t) :: oop_summary
   type(ftimer_mpi_union_summary_t) :: union_summary

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2
   call MPI_Comm_split(MPI_COMM_WORLD, rank, 0, subcomm, ierr)
   if (ierr /= MPI_SUCCESS) error stop 3

   if (rank == 0) then
      summary_file = "consumer_mpi_summary.txt"
      union_summary_file = "consumer_mpi_union_summary.txt"
      union_summary_csv_file = "consumer_mpi_union_summary.csv"
   else
      write (summary_file, '("consumer_mpi_summary_rank",i0,".txt")') rank
      write (union_summary_file, '("consumer_mpi_union_summary_rank",i0,".txt")') rank
      write (union_summary_csv_file, '("consumer_mpi_union_summary_rank",i0,".csv")') rank
   end if

   ! MPI-enabled fTimer must run after MPI_Init and before MPI_Finalize. The
   ! caller-owned subcommunicator captured here is a non-owning handle kept
   ! valid through all summaries, reports, and fTimer finalization below.
   call ftimer_init(comm=subcomm, ierr=ierr)
   if (ierr /= 0) error stop 4

   call ftimer_start("consumer_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 5

   accumulator = 0.0
   do i = 1, (rank + 1)*100000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop("consumer_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 6

   call ftimer_mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 7
   if (summary%num_ranks /= 1) error stop 8
   if (summary%num_entries /= 1) error stop 9
   if (trim(summary%entries(1)%name) /= "consumer_mpi_work") error stop 10
   if (summary%entries(1)%min_inclusive_time < 0.0_wp) error stop 11
   if (summary%entries(1)%max_inclusive_time < summary%entries(1)%min_inclusive_time) error stop 12
   if (summary%entries(1)%avg_inclusive_time < summary%entries(1)%min_inclusive_time) error stop 13
   if (summary%entries(1)%avg_call_count < 1.0_wp) error stop 14
   if (kind(summary%entries(1)%min_call_count) /= int64) error stop 15
   if (kind(summary%entries(1)%max_call_count) /= int64) error stop 16

   call ftimer_mpi_union_summary(union_summary, ierr=ierr)
   if (ierr /= 0) error stop 17
   if (union_summary%num_ranks /= 1) error stop 18
   if (union_summary%num_entries /= 1) error stop 19
   if (trim(union_summary%entries(1)%name) /= "consumer_mpi_work") error stop 20
   if (union_summary%entries(1)%participating_rank_count /= 1) error stop 21
   if (union_summary%entries(1)%avg_call_count < 1.0_wp) error stop 22
   if (kind(union_summary%entries(1)%min_call_count) /= int64) error stop 23
   if (kind(union_summary%entries(1)%max_call_count) /= int64) error stop 24

   call ftimer_write_mpi_summary(summary_file, ierr=ierr)
   if (ierr /= 0) error stop 25

   call ftimer_write_mpi_union_summary(union_summary_file, ierr=ierr)
   if (ierr /= 0) error stop 26

   call ftimer_write_mpi_union_summary_csv(union_summary_csv_file, ierr=ierr)
   if (ierr /= 0) error stop 27

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 28

   call oop_timer%init(comm=subcomm, ierr=ierr)
   if (ierr /= 0) error stop 29

   call oop_timer%start("consumer_oop_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 30

   accumulator = 0.0
   do i = 1, (rank + 1)*50000
      accumulator = accumulator + real(i)
   end do

   call oop_timer%stop("consumer_oop_mpi_work", ierr=ierr)
   if (ierr /= 0) error stop 31

   call oop_timer%mpi_summary(oop_summary, ierr=ierr)
   if (ierr /= 0) error stop 32
   if (oop_summary%num_ranks /= 1) error stop 33
   if (oop_summary%num_entries /= 1) error stop 34
   if (trim(oop_summary%entries(1)%name) /= "consumer_oop_mpi_work") error stop 35

   call oop_timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 36

   call MPI_Comm_free(subcomm, ierr)
   if (ierr /= MPI_SUCCESS) error stop 37

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 38

   if (accumulator < 0.0) print *, accumulator
end program ftimer_installed_mpi_consumer
