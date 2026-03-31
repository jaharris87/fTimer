submodule(ftimer_core) ftimer_core_summary_bindings
   use, intrinsic :: iso_fortran_env, only: error_unit, output_unit
   use ftimer_clock, only: ftimer_date_string
   use ftimer_mpi, only: build_mpi_summary, check_mpi_summary_prereqs, get_mpi_summary_comm_info
   use ftimer_summary, only: build_summary, format_mpi_summary, format_summary
   use ftimer_types, only: FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_UNKNOWN, &
                           ftimer_mpi_summary_t, ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi, only: MPI_Bcast, MPI_CHARACTER, MPI_INTEGER, MPI_SUCCESS
#endif
   implicit none

contains

   module procedure get_summary
   if (.not. self%initialized) then
      call reset_summary(summary)
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer get_summary before init")
      return
   end if

   call build_current_summary(self, summary)
   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure get_summary

   module procedure mpi_summary
   character(len=256) :: diagnostic
   integer :: status

   if (.not. self%initialized) then
      call reset_mpi_summary(summary)
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer mpi_summary before init")
      return
   end if

   call build_current_mpi_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_summary_error(ierr, status, diagnostic)
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure mpi_summary

   module procedure print_summary
   type(ftimer_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: iomsg
   integer :: io
   integer :: out_unit

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer print_summary before init")
      return
   end if

   call build_current_summary(self, summary)
   call format_summary(summary, text, metadata)

   out_unit = output_unit
   if (present(unit)) out_unit = unit

   call write_text_block(out_unit, text, io, iomsg)
   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer print_summary write failed: "//trim(iomsg))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure print_summary

   module procedure write_summary
   type(ftimer_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: iomsg
   integer :: file_unit
   integer :: io
   logical :: append_mode

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_summary before init")
      return
   end if

   call build_current_summary(self, summary)
   call format_summary(summary, text, metadata)

   append_mode = .false.
   if (present(append)) append_mode = append

   if (append_mode) then
      open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
   else
      open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
   end if

   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary open failed: "//trim(iomsg))
      return
   end if

   call write_text_block(file_unit, text, io, iomsg)
   if (io /= 0) then
      close (file_unit)
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary write failed: "//trim(iomsg))
      return
   end if

   close (file_unit, iostat=io, iomsg=iomsg)
   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary close failed: "//trim(iomsg))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_summary

   module procedure print_mpi_summary
   type(ftimer_mpi_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: diagnostic
   character(len=256) :: iomsg
   integer :: active_comm
   integer :: io
   integer :: nprocs
   integer :: out_unit
   integer :: rank
   integer :: status

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer print_mpi_summary before init")
      return
   end if

   call build_current_mpi_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_summary_error(ierr, status, diagnostic)
      return
   end if

   call format_mpi_summary(summary, text, metadata)

#ifdef FTIMER_USE_MPI
   call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer print_mpi_summary communicator lookup failed")
      return
   end if

   if (rank /= 0) then
      if (present(ierr)) ierr = FTIMER_SUCCESS
      return
   end if

   out_unit = output_unit
   if (present(unit)) out_unit = unit

   call write_text_block(out_unit, text, io, iomsg)
   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer print_mpi_summary write failed: "//trim(iomsg))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure print_mpi_summary

   module procedure write_mpi_summary
   type(ftimer_mpi_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: diagnostic
   character(len=256) :: collective_message
   character(len=256) :: iomsg
   integer :: active_comm
   integer :: collective_status
   integer :: file_unit
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: rank
   integer :: status
   logical :: append_mode

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_mpi_summary before init")
      return
   end if

   call build_current_mpi_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_summary_error(ierr, status, diagnostic)
      return
   end if

   call format_mpi_summary(summary, text, metadata)

#ifdef FTIMER_USE_MPI
   call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer write_mpi_summary communicator lookup failed")
      return
   end if

   append_mode = .false.
   if (present(append)) append_mode = append

   collective_status = FTIMER_SUCCESS
   collective_message = ''
   if (rank == 0) then
      if (append_mode) then
         open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
      else
         open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
      end if

      if (io /= 0) then
         collective_status = FTIMER_ERR_IO
         collective_message = "ftimer write_mpi_summary open failed: "//trim(iomsg)
      else
         call write_text_block(file_unit, text, io, iomsg)
         if (io /= 0) then
            close (file_unit)
            collective_status = FTIMER_ERR_IO
            collective_message = "ftimer write_mpi_summary write failed: "//trim(iomsg)
         else
            close (file_unit, iostat=io, iomsg=iomsg)
            if (io /= 0) then
               collective_status = FTIMER_ERR_IO
               collective_message = "ftimer write_mpi_summary close failed: "//trim(iomsg)
            end if
         end if
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_summary status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_summary message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_mpi_summary

   subroutine build_current_summary(self, summary)
      class(ftimer_t), intent(in) :: self
      type(ftimer_summary_t), intent(out) :: summary
      character(len=40) :: end_date
      real(wp) :: end_time

      end_time = self%wtime()
      end_date = ftimer_date_string()

      if (allocated(self%segments)) then
         call build_summary(summary=summary, segments=self%segments, init_wtime=self%init_wtime, init_date=self%init_date, &
                            end_time=end_time, end_date=end_date)
      else
         call build_summary(summary=summary, init_wtime=self%init_wtime, init_date=self%init_date, end_time=end_time, &
                            end_date=end_date)
      end if
   end subroutine build_current_summary

   subroutine build_current_mpi_summary(self, summary, status, diagnostic)
      class(ftimer_t), intent(in) :: self
      type(ftimer_mpi_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out) :: diagnostic
      type(ftimer_summary_t) :: local_summary
      integer :: comm
      logical :: local_has_active_timers

      diagnostic = ''
      comm = -1
      local_has_active_timers = self%call_stack%depth > 0
      call build_current_summary(self, local_summary)
#ifdef FTIMER_USE_MPI
      comm = self%mpi_comm
#endif

      call check_mpi_summary_prereqs(local_has_active_timers, comm, status)
      if (status /= FTIMER_SUCCESS) then
         call reset_mpi_summary(summary)
         return
      end if

      call build_mpi_summary(local_summary, comm, summary, status, diagnostic)
      if (status /= FTIMER_SUCCESS) call reset_mpi_summary(summary)
   end subroutine build_current_mpi_summary

   subroutine reset_summary(summary)
      type(ftimer_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%start_date = ''
      summary%end_date = ''
      summary%total_time = 0.0_wp
      summary%num_entries = 0
   end subroutine reset_summary

   subroutine reset_mpi_summary(summary)
      type(ftimer_mpi_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_total_time = 0.0_wp
      summary%max_total_time = 0.0_wp
      summary%avg_total_time = 0.0_wp
      summary%min_total_time_rank = -1
      summary%max_total_time_rank = -1
      summary%total_time_imbalance = 1.0_wp
   end subroutine reset_mpi_summary

   subroutine report_summary_status(ierr, code, message)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: code
      character(len=*), intent(in) :: message

      if (present(ierr)) then
         ierr = code
      else
         write (error_unit, '(a)') trim(message)
      end if
   end subroutine report_summary_status

   subroutine report_mpi_summary_error(ierr, status, diagnostic)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: status
      character(len=*), intent(in) :: diagnostic

      select case (status)
      case (FTIMER_ERR_NOT_IMPLEMENTED)
         call report_summary_status(ierr, status, "ftimer mpi_summary requires FTIMER_USE_MPI=ON")
      case (FTIMER_ERR_ACTIVE)
         call report_summary_status(ierr, status, &
                                    "ftimer mpi_summary requires all timers stopped before reduction on "// &
                                    "the init communicator")
      case (FTIMER_ERR_MPI_INCON)
         if (len_trim(diagnostic) > 0) then
            call report_summary_status(ierr, status, trim(diagnostic))
         else
            call report_summary_status(ierr, status, &
                                       "ftimer mpi_summary detected inconsistent timer descriptors across "// &
                                       "ranks in the init communicator")
         end if
      case default
         call report_summary_status(ierr, status, "ftimer mpi_summary MPI reduction failed")
      end select
   end subroutine report_mpi_summary_error

   subroutine write_text_block(unit, text, io, iomsg)
      integer, intent(in) :: unit
      character(len=*), intent(in) :: text
      integer, intent(out) :: io
      character(len=*), intent(out) :: iomsg
      character(len=:), allocatable :: line
      integer :: line_start
      integer :: newline_pos

      io = 0
      iomsg = ''
      line_start = 1

      do while (line_start <= len(text))
         newline_pos = index(text(line_start:), new_line('a'))
         if (newline_pos <= 0) then
            line = text(line_start:)
            write (unit, '(a)', iostat=io, iomsg=iomsg) line
            return
         end if

         if (newline_pos == 1) then
            line = ''
         else
            line = text(line_start:line_start + newline_pos - 2)
         end if

         write (unit, '(a)', iostat=io, iomsg=iomsg) line
         if (io /= 0) return

         line_start = line_start + newline_pos
      end do
   end subroutine write_text_block

end submodule ftimer_core_summary_bindings
