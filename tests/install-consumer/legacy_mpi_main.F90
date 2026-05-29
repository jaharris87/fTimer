program ftimer_installed_legacy_mpi_consumer
   use ftimer, only: ftimer_finalize, ftimer_init, ftimer_mpi_summary, ftimer_start, ftimer_stop, &
                     ftimer_write_mpi_summary
   use ftimer_core, only: ftimer_t
   use ftimer_types, only: ftimer_mpi_summary_t
   use mpi
   implicit none
   integer :: i
   integer :: ierr
   integer :: rank
   integer :: subcomm
   integer :: subrank
   real :: accumulator
   type(ftimer_t) :: timer
   type(ftimer_mpi_summary_t) :: summary

   call MPI_Init(ierr)
   if (ierr /= MPI_SUCCESS) error stop 1

   call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 2

   accumulator = 0.0

   ! MPI-enabled fTimer must run inside the MPI lifetime. Communicators passed
   ! to init are non-owning handles, so each one stays valid until every fTimer
   ! summary/report/finalize operation that may use it is complete.
   call timer%init(comm=MPI_COMM_WORLD, ierr=ierr)
   if (ierr /= 0) error stop 3
   call run_oop_work(timer, "legacy_oop_world", rank, ierr)
   if (ierr /= 0) error stop 4
   call timer%mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 5
   if (summary%num_ranks /= 2) error stop 6
   if (trim(summary%entries(1)%name) /= "legacy_oop_world") error stop 7
   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 8

   call MPI_Comm_split(MPI_COMM_WORLD, rank, rank, subcomm, ierr)
   if (ierr /= MPI_SUCCESS) error stop 9
   call MPI_Comm_rank(subcomm, subrank, ierr)
   if (ierr /= MPI_SUCCESS) error stop 10

   ! The split communicator is still owned by this consumer; fTimer borrows it.
   call timer%init(comm=subcomm, ierr=ierr)
   if (ierr /= 0) error stop 11
   call run_oop_work(timer, "legacy_oop_split", rank, ierr)
   if (ierr /= 0) error stop 12
   call timer%mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 13
   if (summary%num_ranks /= 1) error stop 14
   if (summary%entries(1)%min_inclusive_time_rank /= subrank) error stop 15
   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 16

   call ftimer_init(comm=subcomm, ierr=ierr)
   if (ierr /= 0) error stop 17
   call run_procedural_work("legacy_procedural_split", rank, ierr)
   if (ierr /= 0) error stop 18
   call ftimer_mpi_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 19
   if (summary%num_ranks /= 1) error stop 20
   if (trim(summary%entries(1)%name) /= "legacy_procedural_split") error stop 21

   call ftimer_write_mpi_summary("consumer_legacy_mpi_summary.txt", ierr=ierr)
   if (ierr /= 0) error stop 22
   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 23

   ! Free the borrowed subcommunicator only after fTimer no longer needs it.
   call MPI_Comm_free(subcomm, ierr)
   if (ierr /= MPI_SUCCESS) error stop 24

   call MPI_Finalize(ierr)
   if (ierr /= MPI_SUCCESS) error stop 25

   if (accumulator < 0.0) print *, accumulator

contains

   subroutine run_oop_work(active_timer, name, work_rank, ierr)
      type(ftimer_t), intent(inout) :: active_timer
      character(len=*), intent(in) :: name
      integer, intent(in) :: work_rank
      integer, intent(out) :: ierr

      call active_timer%start(name, ierr=ierr)
      if (ierr /= 0) return

      call burn(work_rank)
      call active_timer%stop(name, ierr=ierr)
   end subroutine run_oop_work

   subroutine run_procedural_work(name, work_rank, ierr)
      character(len=*), intent(in) :: name
      integer, intent(in) :: work_rank
      integer, intent(out) :: ierr

      call ftimer_start(name, ierr=ierr)
      if (ierr /= 0) return

      call burn(work_rank)
      call ftimer_stop(name, ierr=ierr)
   end subroutine run_procedural_work

   subroutine burn(work_rank)
      integer, intent(in) :: work_rank

      do i = 1, (work_rank + 1)*10000
         accumulator = accumulator + real(i)
      end do
   end subroutine burn

end program ftimer_installed_legacy_mpi_consumer
