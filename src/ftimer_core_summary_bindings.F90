submodule(ftimer_core) ftimer_core_summary_bindings
   use, intrinsic :: iso_fortran_env, only: error_unit, int64, iostat_end, output_unit
   use ftimer_clock, only: ftimer_date_string
   use ftimer_mpi, only: build_mpi_summary, build_mpi_union_summary, check_mpi_summary_prereqs, &
                         get_mpi_summary_comm_info
   use ftimer_summary, only: build_summary, format_mpi_summary, format_mpi_union_summary, format_summary
   use ftimer_types, only: FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, FTIMER_ERR_UNKNOWN, &
                           ftimer_metadata_t, ftimer_mpi_summary_entry_t, ftimer_mpi_summary_t, &
                           ftimer_mpi_union_summary_entry_t, ftimer_mpi_union_summary_t, &
                           ftimer_summary_entry_t, ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Bcast, MPI_CHARACTER, MPI_INTEGER, MPI_SUCCESS
#endif
   implicit none

   character(len=*), parameter :: FTIMER_CSV_FORMAT_VERSION = '2'
   character(len=*), parameter :: FTIMER_MPI_UNION_CSV_FORMAT_VERSION = '1'
   integer, parameter :: default_report_buffer_capacity = 1024

   type :: report_buffer_t
      character(len=:), allocatable :: chars
      integer :: used = 0
   end type report_buffer_t

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

   module procedure mpi_union_summary
   character(len=256) :: diagnostic
   integer :: status

   if (.not. self%initialized) then
      call reset_mpi_union_summary(summary)
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer mpi_union_summary before init")
      return
   end if

   call build_current_mpi_union_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_union_summary_error(ierr, status, diagnostic)
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure mpi_union_summary

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

   module procedure write_summary_csv
   type(ftimer_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: iomsg
   integer :: file_unit
   integer :: header_status
   integer :: io
   logical :: append_mode
   logical :: include_header

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_summary_csv before init")
      return
   end if

   append_mode = .false.
   if (present(append)) append_mode = append
   call get_csv_header_mode(filename, append_mode, include_header, header_status, iomsg)
   if (header_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, header_status, "ftimer write_summary_csv append validation failed: "//trim(iomsg))
      return
   end if

   call build_current_summary(self, summary)
   call format_summary_csv(summary, text, metadata, include_header=include_header)

   if (append_mode) then
      open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
   else
      open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
   end if

   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary_csv open failed: "//trim(iomsg))
      return
   end if

   call write_text_block(file_unit, text, io, iomsg)
   if (io /= 0) then
      close (file_unit)
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary_csv write failed: "//trim(iomsg))
      return
   end if

   close (file_unit, iostat=io, iomsg=iomsg)
   if (io /= 0) then
      call report_summary_status(ierr, FTIMER_ERR_IO, "ftimer write_summary_csv close failed: "//trim(iomsg))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_summary_csv

   module procedure print_mpi_summary
   type(ftimer_mpi_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: collective_message
   character(len=256) :: diagnostic
   character(len=256) :: iomsg
   integer :: collective_status
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: out_unit
   integer :: rank
   integer :: status
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

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
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
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

   collective_status = FTIMER_SUCCESS
   collective_message = ''
   if (rank == 0) then
      out_unit = output_unit
      if (present(unit)) out_unit = unit

      call write_text_block(out_unit, text, io, iomsg)
      if (io /= 0) then
         collective_status = FTIMER_ERR_IO
         collective_message = "ftimer print_mpi_summary write failed: "//trim(iomsg)
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer print_mpi_summary status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer print_mpi_summary message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
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
   integer :: collective_status
   integer :: file_unit
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: rank
   integer :: status
   logical :: append_mode
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

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
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
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

   module procedure write_mpi_summary_csv
   type(ftimer_mpi_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: diagnostic
   character(len=256) :: collective_message
   character(len=256) :: iomsg
   integer :: collective_status
   integer :: file_unit
   integer :: header_status
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: rank
   integer :: status
   logical :: append_mode
   logical :: include_header
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_mpi_summary_csv before init")
      return
   end if

   call build_current_mpi_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_summary_error(ierr, status, diagnostic)
      return
   end if

#ifdef FTIMER_USE_MPI
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer write_mpi_summary_csv communicator lookup failed")
      return
   end if

   append_mode = .false.
   if (present(append)) append_mode = append

   collective_status = FTIMER_SUCCESS
   collective_message = ''
   if (rank == 0) then
      call get_csv_header_mode(filename, append_mode, include_header, header_status, iomsg)
      if (header_status /= FTIMER_SUCCESS) then
         collective_status = header_status
         collective_message = "ftimer write_mpi_summary_csv append validation failed: "//trim(iomsg)
      else
         call format_mpi_summary_csv(summary, text, metadata, include_header=include_header)

         if (append_mode) then
            open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, iomsg=iomsg)
         else
            open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
         end if

         if (io /= 0) then
            collective_status = FTIMER_ERR_IO
            collective_message = "ftimer write_mpi_summary_csv open failed: "//trim(iomsg)
         else
            call write_text_block(file_unit, text, io, iomsg)
            if (io /= 0) then
               collective_status = FTIMER_ERR_IO
               collective_message = "ftimer write_mpi_summary_csv write failed: "//trim(iomsg)
               close (file_unit)
            else
               close (file_unit, iostat=io, iomsg=iomsg)
               if (io /= 0) then
                  collective_status = FTIMER_ERR_IO
                  collective_message = "ftimer write_mpi_summary_csv close failed: "//trim(iomsg)
               end if
            end if
         end if
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_summary_csv status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_summary_csv message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_mpi_summary_csv

   module procedure print_mpi_union_summary
   type(ftimer_mpi_union_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: collective_message
   character(len=256) :: diagnostic
   character(len=256) :: iomsg
   integer :: collective_status
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: out_unit
   integer :: rank
   integer :: status
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer print_mpi_union_summary before init")
      return
   end if

   call build_current_mpi_union_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_union_summary_error(ierr, status, diagnostic)
      return
   end if

   call format_mpi_union_summary(summary, text, metadata)

#ifdef FTIMER_USE_MPI
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer print_mpi_union_summary communicator lookup failed")
      return
   end if

   collective_status = FTIMER_SUCCESS
   collective_message = ''
   if (rank == 0) then
      out_unit = output_unit
      if (present(unit)) out_unit = unit

      call write_text_block(out_unit, text, io, iomsg)
      if (io /= 0) then
         collective_status = FTIMER_ERR_IO
         collective_message = "ftimer print_mpi_union_summary write failed: "//trim(iomsg)
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer print_mpi_union_summary status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer print_mpi_union_summary message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure print_mpi_union_summary

   module procedure write_mpi_union_summary
   type(ftimer_mpi_union_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: diagnostic
   character(len=256) :: collective_message
   character(len=256) :: iomsg
   integer :: collective_status
   integer :: file_unit
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: rank
   integer :: status
   logical :: append_mode
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_mpi_union_summary before init")
      return
   end if

   call build_current_mpi_union_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_union_summary_error(ierr, status, diagnostic)
      return
   end if

   call format_mpi_union_summary(summary, text, metadata)

#ifdef FTIMER_USE_MPI
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer write_mpi_union_summary communicator lookup failed")
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
         collective_message = "ftimer write_mpi_union_summary open failed: "//trim(iomsg)
      else
         call write_text_block(file_unit, text, io, iomsg)
         if (io /= 0) then
            close (file_unit)
            collective_status = FTIMER_ERR_IO
            collective_message = "ftimer write_mpi_union_summary write failed: "//trim(iomsg)
         else
            close (file_unit, iostat=io, iomsg=iomsg)
            if (io /= 0) then
               collective_status = FTIMER_ERR_IO
               collective_message = "ftimer write_mpi_union_summary close failed: "//trim(iomsg)
            end if
         end if
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_union_summary status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_union_summary message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_mpi_union_summary

   module procedure write_mpi_union_summary_csv
   type(ftimer_mpi_union_summary_t) :: summary
   character(len=:), allocatable :: text
   character(len=256) :: diagnostic
   character(len=256) :: collective_message
   character(len=256) :: iomsg
   integer :: collective_status
   integer :: file_unit
   integer :: header_status
   integer :: io
   integer :: mpierr
   integer :: nprocs
   integer :: rank
   integer :: status
   logical :: append_mode
   logical :: include_header
#ifdef FTIMER_USE_MPI
   type(MPI_Comm) :: active_comm
#else
   integer :: active_comm
#endif

   if (.not. self%initialized) then
      call report_summary_status(ierr, FTIMER_ERR_NOT_INIT, "ftimer write_mpi_union_summary_csv before init")
      return
   end if

   call build_current_mpi_union_summary(self, summary, status, diagnostic)
   if (status /= FTIMER_SUCCESS) then
      call report_mpi_union_summary_error(ierr, status, diagnostic)
      return
   end if

#ifdef FTIMER_USE_MPI
   if (self%mpi_comm_was_present) then
      call get_mpi_summary_comm_info(self%mpi_comm, active_comm, rank, nprocs, status)
   else
      call get_mpi_summary_comm_info(active_comm=active_comm, rank=rank, nprocs=nprocs, status=status)
   end if
#else
   active_comm = -1
   rank = 0
   nprocs = 1
   status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   if (status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, status, "ftimer write_mpi_union_summary_csv communicator lookup failed")
      return
   end if

   append_mode = .false.
   if (present(append)) append_mode = append

   collective_status = FTIMER_SUCCESS
   collective_message = ''
   if (rank == 0) then
      call get_csv_header_mode(filename, append_mode, include_header, header_status, iomsg, &
                               expected_csv_header=mpi_union_csv_header_line(), &
                               schema_description='MPI union CSV format_version '//FTIMER_MPI_UNION_CSV_FORMAT_VERSION, &
                               summary_kind='mpi_union', format_version=FTIMER_MPI_UNION_CSV_FORMAT_VERSION)
      if (header_status /= FTIMER_SUCCESS) then
         collective_status = header_status
         collective_message = "ftimer write_mpi_union_summary_csv append validation failed: "//trim(iomsg)
      else
         call format_mpi_union_summary_csv(summary, text, metadata, include_header=include_header)

         if (append_mode) then
            open (newunit=file_unit, file=filename, status='unknown', position='append', action='write', iostat=io, &
                  iomsg=iomsg)
         else
            open (newunit=file_unit, file=filename, status='replace', action='write', iostat=io, iomsg=iomsg)
         end if

         if (io /= 0) then
            collective_status = FTIMER_ERR_IO
            collective_message = "ftimer write_mpi_union_summary_csv open failed: "//trim(iomsg)
         else
            call write_text_block(file_unit, text, io, iomsg)
            if (io /= 0) then
               collective_status = FTIMER_ERR_IO
               collective_message = "ftimer write_mpi_union_summary_csv write failed: "//trim(iomsg)
               close (file_unit)
            else
               close (file_unit, iostat=io, iomsg=iomsg)
               if (io /= 0) then
                  collective_status = FTIMER_ERR_IO
                  collective_message = "ftimer write_mpi_union_summary_csv close failed: "//trim(iomsg)
               end if
            end if
         end if
      end if
   end if

#ifdef FTIMER_USE_MPI
   call MPI_Bcast(collective_status, 1, MPI_INTEGER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_union_summary_csv status sync failed")
      return
   end if

   call MPI_Bcast(collective_message, len(collective_message), MPI_CHARACTER, 0, active_comm, mpierr)
   if (mpierr /= MPI_SUCCESS) then
      call report_summary_status(ierr, FTIMER_ERR_UNKNOWN, "ftimer write_mpi_union_summary_csv message sync failed")
      return
   end if
#endif

   if (collective_status /= FTIMER_SUCCESS) then
      call report_summary_status(ierr, collective_status, trim(collective_message))
      return
   end if

   if (present(ierr)) ierr = FTIMER_SUCCESS
   end procedure write_mpi_union_summary_csv

   subroutine build_current_summary(self, summary)
      class(ftimer_t), intent(in) :: self
      type(ftimer_summary_t), intent(out) :: summary
      character(len=40) :: end_date
      real(wp) :: end_time

      end_time = self%wtime()
      end_date = ftimer_date_string()

      if (self%num_segments > 0) then
         call build_summary(summary=summary, segments=self%segments(1:self%num_segments), &
                            init_wtime=self%init_wtime, init_date=self%init_date, &
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
      logical :: local_has_active_timers

      diagnostic = ''
      local_has_active_timers = self%call_stack%depth > 0
      call build_current_summary(self, local_summary)
#ifdef FTIMER_USE_MPI
      if (self%mpi_comm_was_present) then
         call check_mpi_summary_prereqs(local_has_active_timers, self%mpi_comm, status)
      else
         call check_mpi_summary_prereqs(local_has_active_timers, status=status)
      end if
#else
      call check_mpi_summary_prereqs(local_has_active_timers, status=status)
#endif
      if (status /= FTIMER_SUCCESS) then
         call reset_mpi_summary(summary)
         return
      end if

#ifdef FTIMER_USE_MPI
      if (self%mpi_comm_was_present) then
         call build_mpi_summary(local_summary, self%mpi_comm, summary, status, diagnostic)
      else
         call build_mpi_summary(local_summary, summary=summary, status=status, diagnostic=diagnostic)
      end if
#else
      call build_mpi_summary(local_summary, summary=summary, status=status, diagnostic=diagnostic)
#endif
      if (status /= FTIMER_SUCCESS) call reset_mpi_summary(summary)
   end subroutine build_current_mpi_summary

   subroutine build_current_mpi_union_summary(self, summary, status, diagnostic)
      class(ftimer_t), intent(in) :: self
      type(ftimer_mpi_union_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out) :: diagnostic
      type(ftimer_summary_t) :: local_summary
      logical :: local_has_active_timers

      diagnostic = ''
      local_has_active_timers = self%call_stack%depth > 0
      call build_current_summary(self, local_summary)
#ifdef FTIMER_USE_MPI
      if (self%mpi_comm_was_present) then
         call check_mpi_summary_prereqs(local_has_active_timers, self%mpi_comm, status)
      else
         call check_mpi_summary_prereqs(local_has_active_timers, status=status)
      end if
#else
      call check_mpi_summary_prereqs(local_has_active_timers, status=status)
#endif
      if (status /= FTIMER_SUCCESS) then
         call reset_mpi_union_summary(summary)
         return
      end if

#ifdef FTIMER_USE_MPI
      if (self%mpi_comm_was_present) then
         call build_mpi_union_summary(local_summary, self%mpi_comm, summary, status, diagnostic)
      else
         call build_mpi_union_summary(local_summary, summary=summary, status=status, diagnostic=diagnostic)
      end if
#else
      call build_mpi_union_summary(local_summary, summary=summary, status=status, diagnostic=diagnostic)
#endif
      if (status /= FTIMER_SUCCESS) call reset_mpi_union_summary(summary)
   end subroutine build_current_mpi_union_summary

   subroutine format_summary_csv(summary, text, metadata, include_header)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header

      if (emit_header) call append_summary_csv_header(buffer)
      call append_local_summary_csv_record(buffer, summary)

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            call append_metadata_csv_record(buffer, 'local', metadata(i))
         end do
      end if

      do i = 1, summary%num_entries
         call append_local_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_report_buffer(buffer, text)
   end subroutine format_summary_csv

   subroutine format_mpi_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header

      if (emit_header) call append_summary_csv_header(buffer)
      call append_mpi_summary_csv_record(buffer, summary)

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            call append_metadata_csv_record(buffer, 'mpi', metadata(i))
         end do
      end if

      do i = 1, summary%num_entries
         call append_mpi_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_report_buffer(buffer, text)
   end subroutine format_mpi_summary_csv

   subroutine format_mpi_union_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header

      if (emit_header) call append_mpi_union_summary_csv_header(buffer)
      call append_mpi_union_summary_csv_record(buffer, summary)

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            call append_mpi_union_metadata_csv_record(buffer, metadata(i))
         end do
      end if

      do i = 1, summary%num_entries
         call append_mpi_union_entry_csv_record(buffer, summary, summary%entries(i))
      end do
      call finish_report_buffer(buffer, text)
   end subroutine format_mpi_union_summary_csv

   subroutine append_summary_csv_header(buffer)
      type(report_buffer_t), intent(inout) :: buffer

      call append_line(buffer, csv_header_line())
   end subroutine append_summary_csv_header

   subroutine append_mpi_union_summary_csv_header(buffer)
      type(report_buffer_t), intent(inout) :: buffer

      call append_line(buffer, mpi_union_csv_header_line())
   end subroutine append_mpi_union_summary_csv_header

   subroutine append_local_summary_csv_record(buffer, summary)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_summary_t), intent(in) :: summary
      type(report_buffer_t) :: row

      call begin_csv_row(row, 'local', 'summary')
      call append_empty_csv_fields(row, 2)
      call append_csv_field(row, summary%start_date)
      call append_csv_field(row, summary%end_date)
      call append_csv_field(row, real_csv_text(summary%total_time))
      call append_csv_field(row, integer_csv_text(summary%num_entries))
      call append_csv_field(row, logical_csv_text(summary%has_active_timers))
      call append_empty_csv_fields(row, 33)
      call append_row(buffer, row)
   end subroutine append_local_summary_csv_record

   subroutine append_mpi_summary_csv_record(buffer, summary)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_summary_t), intent(in) :: summary
      type(report_buffer_t) :: row

      call begin_csv_row(row, 'mpi', 'summary')
      call append_empty_csv_fields(row, 5)
      call append_csv_field(row, integer_csv_text(summary%num_entries))
      call append_empty_csv_fields(row, 1)
      call append_csv_field(row, integer_csv_text(summary%num_ranks))
      call append_csv_field(row, real_csv_text(summary%min_total_time))
      call append_csv_field(row, real_csv_text(summary%avg_total_time))
      call append_csv_field(row, real_csv_text(summary%max_total_time))
      call append_csv_field(row, integer_csv_text(summary%min_total_time_rank))
      call append_csv_field(row, integer_csv_text(summary%max_total_time_rank))
      call append_csv_field(row, real_csv_text(summary%total_time_imbalance))
      call append_empty_csv_fields(row, 26)
      call append_row(buffer, row)
   end subroutine append_mpi_summary_csv_record

   subroutine append_mpi_union_summary_csv_record(buffer, summary)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      type(report_buffer_t) :: row

      call begin_mpi_union_csv_row(row, 'summary')
      call append_empty_csv_fields(row, 2)
      call append_csv_field(row, integer_csv_text(summary%num_entries))
      call append_csv_field(row, integer_csv_text(summary%num_ranks))
      call append_csv_field(row, real_csv_text(summary%min_total_time))
      call append_csv_field(row, real_csv_text(summary%avg_total_time))
      call append_csv_field(row, real_csv_text(summary%max_total_time))
      call append_csv_field(row, integer_csv_text(summary%min_total_time_rank))
      call append_csv_field(row, integer_csv_text(summary%max_total_time_rank))
      call append_csv_field(row, real_csv_text(summary%total_time_imbalance))
      call append_empty_csv_fields(row, 22)
      call append_row(buffer, row)
   end subroutine append_mpi_union_summary_csv_record

   subroutine append_metadata_csv_record(buffer, summary_kind, item)
      type(report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: summary_kind
      type(ftimer_metadata_t), intent(in) :: item
      type(report_buffer_t) :: row

      call begin_csv_row(row, summary_kind, 'metadata')
      call append_csv_field(row, metadata_key_text(item))
      call append_csv_field(row, metadata_value_text(item))
      call append_empty_csv_fields(row, 38)
      call append_row(buffer, row)
   end subroutine append_metadata_csv_record

   subroutine append_mpi_union_metadata_csv_record(buffer, item)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(report_buffer_t) :: row

      call begin_mpi_union_csv_row(row, 'metadata')
      call append_csv_field(row, metadata_key_text(item))
      call append_csv_field(row, metadata_value_text(item))
      call append_empty_csv_fields(row, 30)
      call append_row(buffer, row)
   end subroutine append_mpi_union_metadata_csv_record

   subroutine append_local_entry_csv_record(buffer, entry)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_summary_entry_t), intent(in) :: entry
      type(report_buffer_t) :: row

      call begin_csv_row(row, 'local', 'entry')
      call append_empty_csv_fields(row, 14)
      call append_csv_field(row, integer_csv_text(entry%node_id))
      call append_csv_field(row, integer_csv_text(entry%parent_id))
      call append_csv_field(row, integer_csv_text(entry%depth))
      call append_csv_field(row, summary_entry_name(entry))
      call append_csv_field(row, real_csv_text(entry%inclusive_time))
      call append_csv_field(row, real_csv_text(entry%self_time))
      call append_csv_field(row, int64_csv_text(entry%call_count))
      call append_csv_field(row, real_csv_text(entry%avg_time))
      call append_csv_field(row, real_csv_text(entry%pct_time))
      call append_csv_field(row, logical_csv_text(entry%is_active))
      call append_empty_csv_fields(row, 16)
      call append_row(buffer, row)
   end subroutine append_local_entry_csv_record

   subroutine append_mpi_entry_csv_record(buffer, entry)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_summary_entry_t), intent(in) :: entry
      type(report_buffer_t) :: row

      call begin_csv_row(row, 'mpi', 'entry')
      call append_empty_csv_fields(row, 14)
      call append_csv_field(row, integer_csv_text(entry%node_id))
      call append_csv_field(row, integer_csv_text(entry%parent_id))
      call append_csv_field(row, integer_csv_text(entry%depth))
      call append_csv_field(row, mpi_summary_entry_name(entry))
      call append_empty_csv_fields(row, 6)
      call append_csv_field(row, real_csv_text(entry%min_inclusive_time))
      call append_csv_field(row, real_csv_text(entry%avg_inclusive_time))
      call append_csv_field(row, real_csv_text(entry%max_inclusive_time))
      call append_csv_field(row, integer_csv_text(entry%min_inclusive_time_rank))
      call append_csv_field(row, integer_csv_text(entry%max_inclusive_time_rank))
      call append_csv_field(row, real_csv_text(entry%inclusive_imbalance))
      call append_csv_field(row, real_csv_text(entry%min_self_time))
      call append_csv_field(row, real_csv_text(entry%avg_self_time))
      call append_csv_field(row, real_csv_text(entry%max_self_time))
      call append_csv_field(row, real_csv_text(entry%self_imbalance))
      call append_csv_field(row, int64_csv_text(entry%min_call_count))
      call append_csv_field(row, real_csv_text(entry%avg_call_count))
      call append_csv_field(row, int64_csv_text(entry%max_call_count))
      call append_csv_field(row, real_csv_text(entry%min_pct_time))
      call append_csv_field(row, real_csv_text(entry%avg_pct_time))
      call append_csv_field(row, real_csv_text(entry%max_pct_time))
      call append_row(buffer, row)
   end subroutine append_mpi_entry_csv_record

   subroutine append_mpi_union_entry_csv_record(buffer, summary, entry)
      type(report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      type(ftimer_mpi_union_summary_entry_t), intent(in) :: entry
      type(report_buffer_t) :: row
      integer :: missing_rank_count

      missing_rank_count = summary%num_ranks - entry%participating_rank_count

      call begin_mpi_union_csv_row(row, 'entry')
      call append_empty_csv_fields(row, 10)
      call append_csv_field(row, integer_csv_text(entry%node_id))
      call append_csv_field(row, integer_csv_text(entry%parent_id))
      call append_csv_field(row, integer_csv_text(entry%depth))
      call append_csv_field(row, mpi_union_summary_entry_name(entry))
      call append_csv_field(row, integer_csv_text(entry%participating_rank_count))
      call append_csv_field(row, integer_csv_text(missing_rank_count))
      call append_csv_field(row, real_csv_text(entry%min_inclusive_time))
      call append_csv_field(row, real_csv_text(entry%avg_inclusive_time))
      call append_csv_field(row, real_csv_text(entry%max_inclusive_time))
      call append_csv_field(row, integer_csv_text(entry%min_inclusive_time_rank))
      call append_csv_field(row, integer_csv_text(entry%max_inclusive_time_rank))
      call append_csv_field(row, real_csv_text(entry%inclusive_imbalance))
      call append_csv_field(row, real_csv_text(entry%min_self_time))
      call append_csv_field(row, real_csv_text(entry%avg_self_time))
      call append_csv_field(row, real_csv_text(entry%max_self_time))
      call append_csv_field(row, real_csv_text(entry%self_imbalance))
      call append_csv_field(row, int64_csv_text(entry%min_call_count))
      call append_csv_field(row, real_csv_text(entry%avg_call_count))
      call append_csv_field(row, int64_csv_text(entry%max_call_count))
      call append_csv_field(row, real_csv_text(entry%min_pct_time))
      call append_csv_field(row, real_csv_text(entry%avg_pct_time))
      call append_csv_field(row, real_csv_text(entry%max_pct_time))
      call append_row(buffer, row)
   end subroutine append_mpi_union_entry_csv_record

   subroutine begin_csv_row(row, summary_kind, record_type)
      type(report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: summary_kind
      character(len=*), intent(in) :: record_type

      call init_report_buffer(row, 512)
      call append_csv_field(row, FTIMER_CSV_FORMAT_VERSION)
      call append_csv_field(row, summary_kind)
      call append_csv_field(row, record_type)
   end subroutine begin_csv_row

   subroutine begin_mpi_union_csv_row(row, record_type)
      type(report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_report_buffer(row, 512)
      call append_csv_field(row, FTIMER_MPI_UNION_CSV_FORMAT_VERSION)
      call append_csv_field(row, 'mpi_union')
      call append_csv_field(row, record_type)
   end subroutine begin_mpi_union_csv_row

   subroutine append_empty_csv_fields(row, count)
      type(report_buffer_t), intent(inout) :: row
      integer, intent(in) :: count
      integer :: i

      do i = 1, count
         call append_csv_field(row, '')
      end do
   end subroutine append_empty_csv_fields

   subroutine append_csv_field(row, value)
      type(report_buffer_t), intent(inout) :: row
      character(len=*), intent(in) :: value
      integer :: i

      if (row%used > 0) call append_report_text(row, ',')
      call append_report_text(row, '"')
      do i = 1, len_trim(value)
         if (value(i:i) == '"') then
            call append_report_text(row, '""')
         else
            call append_report_text(row, value(i:i))
         end if
      end do
      call append_report_text(row, '"')
   end subroutine append_csv_field

   function integer_csv_text(value) result(text)
      integer, intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function integer_csv_text

   function int64_csv_text(value) result(text)
      integer(int64), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function int64_csv_text

   function real_csv_text(value) result(text)
      real(wp), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=48) :: buffer

      write (buffer, '(es32.17e4)') value
      text = trim(adjustl(buffer))
   end function real_csv_text

   function logical_csv_text(value) result(text)
      logical, intent(in) :: value
      character(len=:), allocatable :: text

      if (value) then
         text = 'true'
      else
         text = 'false'
      end if
   end function logical_csv_text

   subroutine append_line(buffer, line)
      type(report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: line

      call append_report_text(buffer, trim(line))
      call append_report_text(buffer, new_line('a'))
   end subroutine append_line

   subroutine append_row(buffer, row)
      type(report_buffer_t), intent(inout) :: buffer
      type(report_buffer_t), intent(in) :: row

      if (row%used > 0) call append_report_text(buffer, row%chars(1:row%used))
      call append_report_text(buffer, new_line('a'))
   end subroutine append_row

   subroutine init_report_buffer(buffer, initial_capacity)
      type(report_buffer_t), intent(out) :: buffer
      integer, intent(in) :: initial_capacity
      integer :: capacity

      capacity = max(1, initial_capacity)
      allocate (character(len=capacity) :: buffer%chars)
      buffer%used = 0
   end subroutine init_report_buffer

   subroutine append_report_text(buffer, fragment)
      type(report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: fragment
      integer :: fragment_len
      integer :: next_used

      fragment_len = len(fragment)
      if (fragment_len <= 0) return

      next_used = buffer%used + fragment_len
      call ensure_report_capacity(buffer, next_used)
      buffer%chars(buffer%used + 1:next_used) = fragment
      buffer%used = next_used
   end subroutine append_report_text

   subroutine finish_report_buffer(buffer, text)
      type(report_buffer_t), intent(in) :: buffer
      character(len=:), allocatable, intent(out) :: text

      if (buffer%used > 0) then
         text = buffer%chars(1:buffer%used)
      else
         text = ''
      end if
   end subroutine finish_report_buffer

   subroutine ensure_report_capacity(buffer, required_capacity)
      type(report_buffer_t), intent(inout) :: buffer
      integer, intent(in) :: required_capacity
      character(len=:), allocatable :: grown
      integer :: current_capacity
      integer :: new_capacity

      if (allocated(buffer%chars)) then
         current_capacity = len(buffer%chars)
      else
         current_capacity = 0
      end if
      if (current_capacity >= required_capacity) return

      new_capacity = max(default_report_buffer_capacity, current_capacity)
      if (new_capacity <= 0) new_capacity = default_report_buffer_capacity
      do while (new_capacity < required_capacity)
         if (new_capacity > huge(new_capacity)/2) then
            new_capacity = required_capacity
         else
            new_capacity = new_capacity*2
         end if
      end do

      allocate (character(len=new_capacity) :: grown)
      if (buffer%used > 0) grown(1:buffer%used) = buffer%chars(1:buffer%used)
      call move_alloc(grown, buffer%chars)
   end subroutine ensure_report_capacity

   function summary_entry_name(entry) result(name)
      type(ftimer_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function summary_entry_name

   function mpi_summary_entry_name(entry) result(name)
      type(ftimer_mpi_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_summary_entry_name

   function mpi_union_summary_entry_name(entry) result(name)
      type(ftimer_mpi_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_union_summary_entry_name

   integer function metadata_key_len(item) result(width)
      type(ftimer_metadata_t), intent(in) :: item

      width = 0
      if (allocated(item%key)) width = len_trim(item%key)
   end function metadata_key_len

   function metadata_key_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%key)) then
         text = trim(item%key)
      else
         text = ''
      end if
   end function metadata_key_text

   function metadata_value_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%value)) then
         text = trim(item%value)
      else
         text = ''
      end if
   end function metadata_value_text

   subroutine reset_summary(summary)
      type(ftimer_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%start_date = ''
      summary%end_date = ''
      summary%total_time = 0.0_wp
      summary%num_entries = 0
      summary%has_active_timers = .false.
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

   subroutine reset_mpi_union_summary(summary)
      type(ftimer_mpi_union_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_total_time = 0.0_wp
      summary%max_total_time = 0.0_wp
      summary%avg_total_time = 0.0_wp
      summary%min_total_time_rank = -1
      summary%max_total_time_rank = -1
      summary%total_time_imbalance = 1.0_wp
   end subroutine reset_mpi_union_summary

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
         if (len_trim(diagnostic) > 0) then
            call report_summary_status(ierr, status, trim(diagnostic))
         else
            call report_summary_status(ierr, status, "ftimer mpi_summary MPI reduction failed")
         end if
      end select
   end subroutine report_mpi_summary_error

   subroutine report_mpi_union_summary_error(ierr, status, diagnostic)
      integer, intent(out), optional :: ierr
      integer, intent(in) :: status
      character(len=*), intent(in) :: diagnostic

      select case (status)
      case (FTIMER_ERR_NOT_IMPLEMENTED)
         if (len_trim(diagnostic) > 0) then
            call report_summary_status(ierr, status, trim(diagnostic))
         else
            call report_summary_status(ierr, status, "ftimer mpi_union_summary requires FTIMER_USE_MPI=ON")
         end if
      case (FTIMER_ERR_ACTIVE)
         call report_summary_status(ierr, status, &
                                    "ftimer mpi_union_summary requires all timers stopped before reduction on "// &
                                    "the init communicator")
      case (FTIMER_ERR_MPI_INCON)
         if (len_trim(diagnostic) > 0) then
            call report_summary_status(ierr, status, trim(diagnostic))
         else
            call report_summary_status(ierr, status, &
                                       "ftimer mpi_union_summary detected invalid sparse timer descriptors across "// &
                                       "ranks in the init communicator")
         end if
      case default
         if (len_trim(diagnostic) > 0) then
            call report_summary_status(ierr, status, trim(diagnostic))
         else
            call report_summary_status(ierr, status, "ftimer mpi_union_summary MPI reduction failed")
         end if
      end select
   end subroutine report_mpi_union_summary_error

   subroutine get_csv_header_mode(filename, append_mode, include_header, status, iomsg, expected_csv_header, &
                                  schema_description, summary_kind, format_version)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=*), intent(in), optional :: expected_csv_header
      character(len=*), intent(in), optional :: schema_description
      character(len=*), intent(in), optional :: summary_kind
      character(len=*), intent(in), optional :: format_version
      character(len=1) :: ch
      character(len=:), allocatable :: expected_header
      character(len=:), allocatable :: header_line
      character(len=:), allocatable :: record_text
      character(len=:), allocatable :: schema_name
      integer :: expected_field_count
      integer :: file_unit
      integer :: io
      integer :: record_field_count
      integer :: record_prefix_limit
      character(len=1) :: last_char
      logical :: exists
      logical :: after_quoted_field
      logical :: field_has_content
      logical :: in_quotes
      logical :: pending_record_cr
      logical :: pending_quote
      logical :: reading_header
      logical :: saw_any_char

      include_header = .true.
      status = FTIMER_SUCCESS
      iomsg = ''
      if (.not. append_mode) return

      exists = .false.
      inquire (file=filename, exist=exists)
      if (.not. exists) return

      if (present(expected_csv_header)) then
         expected_header = expected_csv_header
      else
         expected_header = csv_header_line()
      end if
      if (present(schema_description)) then
         schema_name = trim(schema_description)
      else
         schema_name = 'CSV format_version '//FTIMER_CSV_FORMAT_VERSION
      end if
      expected_field_count = csv_field_count(expected_header)
      record_prefix_limit = 64
      header_line = ''
      record_text = ''
      record_field_count = 1
      last_char = ''
      reading_header = .true.
      after_quoted_field = .false.
      field_has_content = .false.
      in_quotes = .false.
      pending_record_cr = .false.
      pending_quote = .false.
      saw_any_char = .false.

      open (newunit=file_unit, file=filename, status='old', access='stream', form='unformatted', &
            action='read', iostat=io, iomsg=iomsg)
      if (io /= 0) then
         status = FTIMER_ERR_IO
         return
      end if

      do
         read (file_unit, iostat=io, iomsg=iomsg) ch
         if (io == iostat_end) exit
         if (io /= 0) then
            close (file_unit)
            status = FTIMER_ERR_IO
            return
         end if

         last_char = ch
         saw_any_char = .true.

         if (reading_header) then
            if (ch == new_line('a')) then
               reading_header = .false.
               call strip_trailing_carriage_return(header_line)
               if ((len(header_line) /= len(expected_header)) .or. (header_line /= expected_header)) then
                  close (file_unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing CSV header does not match fTimer '//schema_name
                  return
               end if
            else
               if (len(header_line) >= len(expected_header) + 1) then
                  close (file_unit)
                  status = FTIMER_ERR_IO
                  iomsg = 'existing CSV header does not match fTimer '//schema_name
                  return
               end if
               header_line = header_line//ch
            end if
            cycle
         end if

         if (pending_record_cr) then
            if (ch /= new_line('a')) then
               close (file_unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing CSV records contain a bare carriage return'
               return
            end if
            pending_record_cr = .false.
         end if

         if (pending_quote) then
            if (ch == '"') then
               pending_quote = .false.
               call append_limited_csv_record_prefix(record_text, ch, record_prefix_limit)
               cycle
            end if
            in_quotes = .false.
            pending_quote = .false.
            after_quoted_field = .true.
         end if

         if ((ch == achar(13)) .and. (.not. in_quotes)) then
            pending_record_cr = .true.
            cycle
         end if

         if (after_quoted_field) then
            if ((ch /= ',') .and. (ch /= new_line('a'))) then
               close (file_unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing CSV records contain malformed quoted fields'
               return
            end if
         end if

         if ((ch == new_line('a')) .and. (.not. in_quotes)) then
            call strip_trailing_carriage_return(record_text)
            if ((record_field_count /= expected_field_count) .or. &
                (.not. csv_record_has_valid_prefix(record_text, summary_kind=summary_kind, &
                                                   format_version=format_version))) then
               close (file_unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing CSV records do not match fTimer '//schema_name
               return
            end if
            record_text = ''
            record_field_count = 1
            after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         call append_limited_csv_record_prefix(record_text, ch, record_prefix_limit)

         if ((ch == ',') .and. (.not. in_quotes)) then
            record_field_count = record_field_count + 1
            if (after_quoted_field) after_quoted_field = .false.
            field_has_content = .false.
            cycle
         end if

         if (ch == '"') then
            if (in_quotes) then
               pending_quote = .true.
            else if (field_has_content) then
               close (file_unit)
               status = FTIMER_ERR_IO
               iomsg = 'existing CSV records contain malformed quoted fields'
               return
            else
               in_quotes = .true.
               after_quoted_field = .false.
            end if
         else if (.not. in_quotes) then
            field_has_content = .true.
         end if
      end do
      close (file_unit)

      if (.not. saw_any_char) return

      if (last_char /= new_line('a')) then
         status = FTIMER_ERR_IO
         iomsg = 'existing CSV append target does not end with a newline'
         return
      end if

      if (in_quotes) then
         status = FTIMER_ERR_IO
         iomsg = 'existing CSV records contain an unterminated quoted field'
         return
      end if

      if (pending_record_cr) then
         status = FTIMER_ERR_IO
         iomsg = 'existing CSV records contain a bare carriage return'
         return
      end if

      include_header = .false.
   end subroutine get_csv_header_mode

   subroutine append_limited_csv_record_prefix(record_text, ch, prefix_limit)
      character(len=:), allocatable, intent(inout) :: record_text
      character(len=1), intent(in) :: ch
      integer, intent(in) :: prefix_limit

      if (len(record_text) >= prefix_limit) return
      record_text = record_text//ch
   end subroutine append_limited_csv_record_prefix

   subroutine strip_trailing_carriage_return(text)
      character(len=:), allocatable, intent(inout) :: text
      integer :: text_len

      text_len = len(text)
      if (text_len <= 0) return
      if (text(text_len:text_len) == achar(13)) text = text(:text_len - 1)
   end subroutine strip_trailing_carriage_return

   integer function csv_field_count(line) result(count)
      character(len=*), intent(in) :: line
      integer :: i
      logical :: in_quotes

      count = 1
      in_quotes = .false.
      do i = 1, len_trim(line)
         if (line(i:i) == '"') then
            in_quotes = .not. in_quotes
         else if ((line(i:i) == ',') .and. (.not. in_quotes)) then
            count = count + 1
         end if
      end do
   end function csv_field_count

   logical function csv_record_has_valid_prefix(line, summary_kind, format_version) result(matches)
      character(len=*), intent(in) :: line
      character(len=*), intent(in), optional :: summary_kind
      character(len=*), intent(in), optional :: format_version
      character(len=:), allocatable :: row_format_version

      row_format_version = FTIMER_CSV_FORMAT_VERSION
      if (present(format_version)) row_format_version = trim(format_version)

      if (present(summary_kind)) then
         matches = starts_with(line, '"'//row_format_version//'","'//trim(summary_kind)//'","summary",') .or. &
                   starts_with(line, '"'//row_format_version//'","'//trim(summary_kind)//'","metadata",') .or. &
                   starts_with(line, '"'//row_format_version//'","'//trim(summary_kind)//'","entry",')
      else
         matches = starts_with(line, '"'//row_format_version//'","local","summary",') .or. &
                   starts_with(line, '"'//row_format_version//'","local","metadata",') .or. &
                   starts_with(line, '"'//row_format_version//'","local","entry",') .or. &
                   starts_with(line, '"'//row_format_version//'","mpi","summary",') .or. &
                   starts_with(line, '"'//row_format_version//'","mpi","metadata",') .or. &
                   starts_with(line, '"'//row_format_version//'","mpi","entry",')
      end if
   end function csv_record_has_valid_prefix

   logical function starts_with(text, prefix) result(matches)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: prefix

      matches = .false.
      if (len_trim(text) < len(prefix)) return
      matches = text(1:len(prefix)) == prefix
   end function starts_with

   function csv_header_line() result(header)
      character(len=:), allocatable :: header

      header = 'format_version,summary_kind,record_type,key,value,start_date,end_date,total_time,'// &
               'num_entries,has_active_timers,num_ranks,min_total_time,avg_total_time,max_total_time,'// &
               'min_total_time_rank,max_total_time_rank,total_time_imbalance,node_id,parent_id,depth,'// &
               'name,inclusive_time,self_time,call_count,avg_time,pct_time,is_active,min_inclusive_time,'// &
               'avg_inclusive_time,max_inclusive_time,min_inclusive_time_rank,max_inclusive_time_rank,'// &
               'inclusive_imbalance,min_self_time,avg_self_time,max_self_time,self_imbalance,'// &
               'min_call_count,avg_call_count,max_call_count,min_pct_time,avg_pct_time,max_pct_time'
   end function csv_header_line

   function mpi_union_csv_header_line() result(header)
      character(len=:), allocatable :: header

      header = 'format_version,summary_kind,record_type,key,value,num_entries,num_ranks,min_total_time,'// &
               'avg_total_time,max_total_time,min_total_time_rank,max_total_time_rank,total_time_imbalance,'// &
               'node_id,parent_id,depth,name,participating_rank_count,missing_rank_count,'// &
               'min_participating_inclusive_time,avg_participating_inclusive_time,'// &
               'max_participating_inclusive_time,min_participating_inclusive_time_rank,'// &
               'max_participating_inclusive_time_rank,participating_inclusive_imbalance,'// &
               'min_participating_self_time,avg_participating_self_time,max_participating_self_time,'// &
               'participating_self_imbalance,min_participating_call_count,avg_participating_call_count,'// &
               'max_participating_call_count,min_participating_pct_time,avg_participating_pct_time,'// &
               'max_participating_pct_time'
   end function mpi_union_csv_header_line

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
