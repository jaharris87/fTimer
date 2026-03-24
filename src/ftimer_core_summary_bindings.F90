submodule(ftimer_core) ftimer_core_summary_bindings
   use, intrinsic :: iso_fortran_env, only: error_unit, output_unit
   use ftimer_clock, only: ftimer_date_string
   use ftimer_mpi, only: augment_summary_with_mpi, check_mpi_summary_prereqs
   use ftimer_summary, only: build_summary, format_summary
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED
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
   integer :: comm
   integer :: status
   logical :: local_has_active_timers

   if (.not. self%initialized) then
      call reset_summary(summary)
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer mpi_summary before init")
      return
   end if

   comm = -1
   local_has_active_timers = self%call_stack%depth > 0
   call build_current_summary(self, summary)
#ifdef FTIMER_USE_MPI
   ! mpi_summary() is collective over the communicator captured during init.
   comm = self%mpi_comm
#endif
   call check_mpi_summary_prereqs(local_has_active_timers, comm, status)
   if (status /= FTIMER_SUCCESS) then
      select case (status)
      case (FTIMER_ERR_NOT_IMPLEMENTED)
         call report_summary_status(ierr, status, "ftimer mpi_summary requires FTIMER_USE_MPI=ON; using local summary")
      case (FTIMER_ERR_ACTIVE)
         call report_summary_status(ierr, status, &
                                    "ftimer mpi_summary requires all timers stopped before reduction on "// &
                                    "the init communicator; using local summary")
      case default
         call report_summary_status(ierr, status, &
                                    "ftimer mpi_summary communicator precheck failed; using local summary")
      end select
      return
   end if

   call augment_summary_with_mpi(summary, comm, status)
   if (status /= FTIMER_SUCCESS) then
      if (status == FTIMER_ERR_MPI_INCON) then
         call report_summary_status(ierr, status, &
                                    "ftimer mpi_summary detected inconsistent timer descriptors across "// &
                                    "ranks in the init communicator; using local summary")
      else
         call report_summary_status(ierr, status, "ftimer mpi_summary MPI reduction failed")
      end if
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

   subroutine reset_summary(summary)
      type(ftimer_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%start_date = ''
      summary%end_date = ''
      summary%total_time = 0.0_wp
      summary%has_mpi_data = .false.
      summary%num_entries = 0
      summary%placeholder = 0
   end subroutine reset_summary

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
