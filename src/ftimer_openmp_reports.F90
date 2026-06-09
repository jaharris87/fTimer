submodule(ftimer_openmp) ftimer_openmp_reports
   implicit none

contains

   module subroutine format_mpi_openmp_mismatch_diagnostic(mismatch_flags, reason, diagnostic)
      integer, intent(in) :: mismatch_flags(:)
      character(len=*), intent(in) :: reason
      character(len=*), intent(out) :: diagnostic
      character(len=*), parameter :: base_message = &
                                     "ftimer_openmp mpi_openmp_summary detected inconsistent strict hybrid descriptors"
      character(len=*), parameter :: rank_prefix = "; disagreeing ranks "
      character(len=32) :: rank_text
      character(len=len(diagnostic)) :: rank_list
      integer :: available_len
      integer :: i

      diagnostic = trim(base_message)//" ("//trim(reason)//")"
      rank_list = ''
      available_len = len(diagnostic) - len_trim(diagnostic) - len(rank_prefix)
      if (available_len <= 0) return

      do i = 1, size(mismatch_flags)
         if (mismatch_flags(i) == 0) cycle
         write (rank_text, '(i0)') i - 1
         if (len_trim(rank_list) <= 0) then
            if (len_trim(rank_text) <= available_len) rank_list = trim(rank_text)
         else
            if (len_trim(rank_list) + 2 + len_trim(rank_text) <= available_len) then
               rank_list = trim(rank_list)//", "//trim(rank_text)
            end if
         end if
      end do

      if (len_trim(rank_list) > 0) diagnostic = trim(diagnostic)//rank_prefix//trim(rank_list)
   end subroutine format_mpi_openmp_mismatch_diagnostic

   module subroutine format_mpi_openmp_summary(summary, text, metadata)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      character(len=:), allocatable :: missing_samples_text
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'MPI+OpenMP summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Ranks'))
      key_width = max(key_width, len('Rank summary window min/avg/max (s)'))
      key_width = max(key_width, len('Rank timed-region envelope min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane root work min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane self work min/avg/max (s)'))

      call append_openmp_integer_metric(buffer, 'Ranks', key_width, summary%num_ranks)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summary window min/avg/max (s)', key_width, &
                                                 summary%min_rank_summary_window_time, &
                                                 summary%avg_rank_summary_window_time, &
                                                 summary%max_rank_summary_window_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank timed-region envelope min/avg/max (s)', key_width, &
                                                 summary%min_rank_timed_region_envelope_time, &
                                                 summary%avg_rank_timed_region_envelope_time, &
                                                 summary%max_rank_timed_region_envelope_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane root work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_root_inclusive_time, &
                                                 summary%avg_rank_sum_lane_root_inclusive_time, &
                                                 summary%max_rank_sum_lane_root_inclusive_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane self work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_self_time, &
                                                 summary%avg_rank_sum_lane_self_time, &
                                                 summary%max_rank_sum_lane_self_time)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: strict hybrid reductions require every rank and eligible lane to match.')
      call append_openmp_line(buffer, 'Report note: Rank/lane samples are not zero-filled.')
      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, 'Rank details')
      call append_openmp_line(buffer, &
                              'Rank  Lanes  Window (s)  Rank timed-region envelope (s)  Lane root work (s)  Lane self work (s)')
      do i = 1, size(summary%ranks)
         allocate (character(len=160) :: line)
         write (line, '(i4,2x,i5,2x,f10.6,2x,f32.6,2x,f18.6,2x,f18.6)') &
            summary%ranks(i)%rank, summary%ranks(i)%observed_participating_lane_count, &
            summary%ranks(i)%summary_window_time, summary%ranks(i)%timed_region_envelope_time, &
            summary%ranks(i)%sum_lane_root_inclusive_time, summary%ranks(i)%sum_lane_self_time
         call append_openmp_line(buffer, trim(line))
         deallocate (line)
      end do

      call append_openmp_line(buffer, '')
      name_width = mpi_openmp_summary_name_width(summary)
      line_width = name_width + 230
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Domain', 'Ranks', 'Rank/lane samples', &
         'Missing', 'Sum Incl (s)', 'Sum Self (s)', 'Min Incl (s)', 'Avg Incl (s)', &
         'Max Incl (s)', 'Avg Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//mpi_openmp_entry_name(summary%entries(i))
         write (line, '(a,2x,a,2x,i5,2x,i17,2x,i7,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f9.3)') &
            padded_openmp_text(display, name_width), mpi_openmp_entry_domain(summary%entries(i)), &
            summary%entries(i)%participating_rank_count, &
            summary%entries(i)%participating_rank_lane_sample_count, &
            summary%entries(i)%missing_rank_lane_sample_count, &
            summary%entries(i)%sum_participating_lane_inclusive_time, &
            summary%entries(i)%sum_participating_lane_self_time, &
            summary%entries(i)%min_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_inclusive_time, &
            summary%entries(i)%max_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_summary

   subroutine append_mpi_openmp_real_triplet_metric(buffer, label, key_width, min_value, avg_value, max_value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      real(wp), intent(in) :: min_value
      real(wp), intent(in) :: avg_value
      real(wp), intent(in) :: max_value
      character(len=160) :: value_text

      write (value_text, '(f0.6," / ",f0.6," / ",f0.6)') min_value, avg_value, max_value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_mpi_openmp_real_triplet_metric

   integer function mpi_openmp_summary_name_width(summary) result(width)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(mpi_openmp_entry_name(summary%entries(i))))
      end do
   end function mpi_openmp_summary_name_width

   function mpi_openmp_entry_name(entry) result(name)
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_openmp_entry_name

   function mpi_openmp_entry_domain(entry) result(domain)
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: domain

      if (allocated(entry%execution_domain)) then
         domain = entry%execution_domain
      else
         domain = ''
      end if
   end function mpi_openmp_entry_domain

   module subroutine format_mpi_openmp_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header
      if (emit_header) call append_openmp_line(buffer, mpi_openmp_csv_header_line())
      call append_mpi_openmp_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_mpi_openmp_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, size(summary%ranks)
         call append_mpi_openmp_rank_csv_record(buffer, summary%ranks(i))
      end do
      do i = 1, summary%num_entries
         call append_mpi_openmp_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_summary_csv

   subroutine append_mpi_openmp_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_ranks))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 7)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_summary_window_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_timed_region_envelope_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_root_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_self_imbalance))
      call append_empty_openmp_csv_fields(row, 28)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_summary_csv_record

   subroutine append_mpi_openmp_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 53)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_metadata_csv_record

   subroutine append_mpi_openmp_rank_csv_record(buffer, rank_entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_rank_t), intent(in) :: rank_entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'rank')
      call append_empty_openmp_csv_fields(row, 4)
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%rank))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_self_time))
      call append_empty_openmp_csv_fields(row, 44)
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_rank_csv_record

   subroutine append_mpi_openmp_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 27)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, mpi_openmp_entry_name(entry))
      call append_openmp_csv_field(row, mpi_openmp_entry_domain(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_rank_lane_sample_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_pct_imbalance))
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_entry_csv_record

   subroutine begin_mpi_openmp_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'mpi_openmp')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_mpi_openmp_csv_row

   function mpi_openmp_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 2048)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'num_ranks')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'rank')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_rank_summary_window_time')
      call append_openmp_csv_field(row, 'avg_rank_summary_window_time')
      call append_openmp_csv_field(row, 'max_rank_summary_window_time')
      call append_openmp_csv_field(row, 'rank_summary_window_imbalance')
      call append_openmp_csv_field(row, 'min_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'avg_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'max_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'rank_timed_region_envelope_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_root_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_self_imbalance')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'execution_domain')
      call append_openmp_csv_field(row, 'participating_rank_count')
      call append_openmp_csv_field(row, 'missing_rank_count')
      call append_openmp_csv_field(row, 'eligible_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'participating_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count_known')
      call append_openmp_csv_field(row, 'sum_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_participating_lane_self_time')
      call append_openmp_csv_field(row, 'min_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'participating_lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_self_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_self_time')
      call append_openmp_csv_field(row, 'max_participating_lane_self_time')
      call append_openmp_csv_field(row, 'participating_lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_call_count')
      call append_openmp_csv_field(row, 'avg_participating_lane_call_count')
      call append_openmp_csv_field(row, 'max_participating_lane_call_count')
      call append_openmp_csv_field(row, 'min_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'max_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'participating_lane_pct_imbalance')
      call finish_openmp_report_buffer(row, line)
   end function mpi_openmp_csv_header_line

   module subroutine get_mpi_openmp_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=:), allocatable :: expected_header

      expected_header = mpi_openmp_csv_header_line()
      call ftimer_get_csv_append_header_mode(filename, append_mode, include_header, status, iomsg, &
                                             expected_header, FTIMER_MPI_OPENMP_CSV_FORMAT_VERSION, &
                                             [character(len=11) :: 'mpi_openmp'], &
                                             [character(len=8) :: 'summary', 'metadata', 'rank', 'entry'], &
                                             'existing MPI+OpenMP summary CSV header does not match format version 1', &
                                             'existing MPI+OpenMP summary CSV records do not match format version 1', &
                                             'existing MPI+OpenMP summary CSV records contain a bare carriage return', &
                                             'existing MPI+OpenMP summary CSV records contain malformed quoted fields', &
                                             'existing MPI+OpenMP summary CSV append target does not end with a newline', &
                                             'existing MPI+OpenMP summary CSV records contain an unterminated quoted field')
   end subroutine get_mpi_openmp_csv_header_mode

   module subroutine format_mpi_openmp_union_summary(summary, text, metadata)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      character(len=:), allocatable :: missing_samples_text
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'Sparse MPI+OpenMP union summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Ranks'))
      key_width = max(key_width, len('Rank summary window min/avg/max (s)'))
      key_width = max(key_width, len('Rank timed-region envelope min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane root work min/avg/max (s)'))
      key_width = max(key_width, len('Rank summed lane self work min/avg/max (s)'))

      call append_openmp_integer_metric(buffer, 'Ranks', key_width, summary%num_ranks)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summary window min/avg/max (s)', key_width, &
                                                 summary%min_rank_summary_window_time, &
                                                 summary%avg_rank_summary_window_time, &
                                                 summary%max_rank_summary_window_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank timed-region envelope min/avg/max (s)', key_width, &
                                                 summary%min_rank_timed_region_envelope_time, &
                                                 summary%avg_rank_timed_region_envelope_time, &
                                                 summary%max_rank_timed_region_envelope_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane root work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_root_inclusive_time, &
                                                 summary%avg_rank_sum_lane_root_inclusive_time, &
                                                 summary%max_rank_sum_lane_root_inclusive_time)
      call append_mpi_openmp_real_triplet_metric(buffer, 'Rank summed lane self work min/avg/max (s)', key_width, &
                                                 summary%min_rank_sum_lane_self_time, &
                                                 summary%avg_rank_sum_lane_self_time, &
                                                 summary%max_rank_sum_lane_self_time)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: sparse union reductions preserve missing ranks and missing lane samples.')
      call append_openmp_line(buffer, 'Report note: Rank/lane samples are not zero-filled.')
      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, 'Rank details')
      call append_openmp_line(buffer, &
                              'Rank  Lanes  Window (s)  Rank timed-region envelope (s)  Lane root work (s)  Lane self work (s)')
      do i = 1, size(summary%ranks)
         allocate (character(len=160) :: line)
         write (line, '(i4,2x,i5,2x,f10.6,2x,f32.6,2x,f18.6,2x,f18.6)') &
            summary%ranks(i)%rank, summary%ranks(i)%observed_participating_lane_count, &
            summary%ranks(i)%summary_window_time, summary%ranks(i)%timed_region_envelope_time, &
            summary%ranks(i)%sum_lane_root_inclusive_time, summary%ranks(i)%sum_lane_self_time
         call append_openmp_line(buffer, trim(line))
         deallocate (line)
      end do

      call append_openmp_line(buffer, '')
      name_width = mpi_openmp_union_summary_name_width(summary)
      line_width = name_width + 260
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Domain', 'Ranks', 'Missing ranks', &
         'Rank/lane samples', 'Missing samples', 'Sum Incl (s)', 'Sum Self (s)', &
         'Min Incl (s)', 'Avg Incl (s)', 'Max Incl (s)', 'Avg Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//mpi_openmp_union_entry_name(summary%entries(i))
         missing_samples_text = mpi_openmp_union_missing_sample_text(summary%entries(i))
         write (line, '(a,2x,a,2x,i5,2x,i13,2x,i17,2x,a,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f12.6,2x,f9.3)') &
            padded_openmp_text(display, name_width), mpi_openmp_union_entry_domain(summary%entries(i)), &
            summary%entries(i)%participating_rank_count, summary%entries(i)%missing_rank_count, &
            summary%entries(i)%participating_rank_lane_sample_count, &
            padded_openmp_text(missing_samples_text, len('Missing samples')), &
            summary%entries(i)%sum_participating_lane_inclusive_time, &
            summary%entries(i)%sum_participating_lane_self_time, &
            summary%entries(i)%min_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_inclusive_time, &
            summary%entries(i)%max_participating_lane_inclusive_time, &
            summary%entries(i)%avg_participating_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_union_summary

   function mpi_openmp_union_missing_sample_text(entry) result(text)
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: text
      character(len=32) :: value

      if (.not. entry%missing_rank_lane_sample_count_known) then
         text = 'unknown'
         return
      end if

      write (value, '(i0)') entry%missing_rank_lane_sample_count
      text = trim(value)
   end function mpi_openmp_union_missing_sample_text

   integer function mpi_openmp_union_summary_name_width(summary) result(width)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(mpi_openmp_union_entry_name(summary%entries(i))))
      end do
   end function mpi_openmp_union_summary_name_width

   function mpi_openmp_union_entry_name(entry) result(name)
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function mpi_openmp_union_entry_name

   function mpi_openmp_union_entry_domain(entry) result(domain)
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: domain

      if (allocated(entry%execution_domain)) then
         domain = entry%execution_domain
      else
         domain = ''
      end if
   end function mpi_openmp_union_entry_domain

   module subroutine format_mpi_openmp_union_summary_csv(summary, text, metadata, include_header)
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header
      if (emit_header) call append_openmp_line(buffer, mpi_openmp_union_csv_header_line())
      call append_mpi_openmp_union_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_mpi_openmp_union_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, size(summary%ranks)
         call append_mpi_openmp_union_rank_csv_record(buffer, summary%ranks(i))
      end do
      do i = 1, summary%num_entries
         call append_mpi_openmp_union_entry_csv_record(buffer, summary%entries(i))
      end do
      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_mpi_openmp_union_summary_csv

   subroutine append_mpi_openmp_union_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_ranks))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 7)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_summary_window_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_timed_region_envelope_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_root_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%min_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%avg_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%max_rank_sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%rank_sum_lane_self_imbalance))
      call append_empty_openmp_csv_fields(row, 28)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_summary_csv_record

   subroutine append_mpi_openmp_union_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 53)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_metadata_csv_record

   subroutine append_mpi_openmp_union_rank_csv_record(buffer, rank_entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_rank_t), intent(in) :: rank_entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'rank')
      call append_empty_openmp_csv_fields(row, 4)
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%rank))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(rank_entry%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(rank_entry%sum_lane_self_time))
      call append_empty_openmp_csv_fields(row, 44)
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_rank_csv_record

   subroutine append_mpi_openmp_union_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_mpi_openmp_union_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_mpi_openmp_union_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 27)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, mpi_openmp_union_entry_name(entry))
      call append_openmp_csv_field(row, mpi_openmp_union_entry_domain(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_rank_lane_sample_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_rank_lane_sample_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_participating_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_participating_lane_pct_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%participating_lane_pct_imbalance))
      call append_openmp_csv_field(row, 'sparse_union')
      call append_openmp_row(buffer, row)
   end subroutine append_mpi_openmp_union_entry_csv_record

   subroutine begin_mpi_openmp_union_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'mpi_openmp_union')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_mpi_openmp_union_csv_row

   function mpi_openmp_union_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 2048)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'num_ranks')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'rank')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_rank_summary_window_time')
      call append_openmp_csv_field(row, 'avg_rank_summary_window_time')
      call append_openmp_csv_field(row, 'max_rank_summary_window_time')
      call append_openmp_csv_field(row, 'rank_summary_window_imbalance')
      call append_openmp_csv_field(row, 'min_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'avg_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'max_rank_timed_region_envelope_time')
      call append_openmp_csv_field(row, 'rank_timed_region_envelope_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_root_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'avg_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'max_rank_sum_lane_self_time')
      call append_openmp_csv_field(row, 'rank_sum_lane_self_imbalance')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'execution_domain')
      call append_openmp_csv_field(row, 'participating_rank_count')
      call append_openmp_csv_field(row, 'missing_rank_count')
      call append_openmp_csv_field(row, 'eligible_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'participating_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count')
      call append_openmp_csv_field(row, 'missing_rank_lane_sample_count_known')
      call append_openmp_csv_field(row, 'sum_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_participating_lane_self_time')
      call append_openmp_csv_field(row, 'min_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_participating_lane_inclusive_time')
      call append_openmp_csv_field(row, 'participating_lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_self_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_self_time')
      call append_openmp_csv_field(row, 'max_participating_lane_self_time')
      call append_openmp_csv_field(row, 'participating_lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_participating_lane_call_count')
      call append_openmp_csv_field(row, 'avg_participating_lane_call_count')
      call append_openmp_csv_field(row, 'max_participating_lane_call_count')
      call append_openmp_csv_field(row, 'min_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'avg_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'max_participating_lane_pct_time')
      call append_openmp_csv_field(row, 'participating_lane_pct_imbalance')
      call append_openmp_csv_field(row, 'participation_policy')
      call finish_openmp_report_buffer(row, line)
   end function mpi_openmp_union_csv_header_line

   module subroutine get_mpi_openmp_union_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=:), allocatable :: expected_header

      expected_header = mpi_openmp_union_csv_header_line()
      call ftimer_get_csv_append_header_mode(filename, append_mode, include_header, status, iomsg, &
                                             expected_header, FTIMER_MPI_OPENMP_UNION_CSV_FORMAT_VERSION, &
                                             [character(len=17) :: 'mpi_openmp_union'], &
                                             [character(len=8) :: 'summary', 'metadata', 'rank', 'entry'], &
                                             'existing sparse MPI+OpenMP union summary CSV header does not match '// &
                                             'format version 1', &
                                             'existing sparse MPI+OpenMP union summary CSV records do not match format version 1', &
                                             'existing sparse MPI+OpenMP union summary CSV records contain a bare '// &
                                             'carriage return', &
                                             'existing sparse MPI+OpenMP union summary CSV records contain malformed '// &
                                             'quoted fields', &
                                             'existing sparse MPI+OpenMP union summary CSV append target does not end '// &
                                             'with a newline', &
                                             'existing sparse MPI+OpenMP union summary CSV records contain an '// &
                                             'unterminated quoted field')
   end subroutine get_mpi_openmp_union_csv_header_mode

   module subroutine format_openmp_summary(summary, text, metadata)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      type(openmp_report_buffer_t) :: buffer
      character(len=:), allocatable :: display
      character(len=:), allocatable :: line
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: missing_width
      integer :: name_width

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      call append_openmp_line(buffer, 'OpenMP summary')

      key_width = openmp_metadata_key_width(metadata)
      key_width = max(key_width, len('Summary window time (s)'))
      key_width = max(key_width, len('Timed region envelope time (s)'))
      key_width = max(key_width, len('Configured lane capacity'))
      key_width = max(key_width, len('Observed participating lanes'))
      key_width = max(key_width, len('Summed lane root work (s)'))
      key_width = max(key_width, len('Summed lane self work (s)'))

      call append_openmp_real_metric(buffer, 'Summary window time (s)', key_width, summary%summary_window_time)
      call append_openmp_real_metric(buffer, 'Timed region envelope time (s)', key_width, &
                                     summary%timed_region_envelope_time)
      call append_openmp_integer_metric(buffer, 'Configured lane capacity', key_width, &
                                        summary%configured_lane_capacity)
      call append_openmp_integer_metric(buffer, 'Observed participating lanes', key_width, &
                                        summary%observed_participating_lane_count)
      call append_openmp_real_metric(buffer, 'Summed lane root work (s)', key_width, &
                                     summary%sum_lane_root_inclusive_time)
      call append_openmp_real_metric(buffer, 'Summed lane self work (s)', key_width, summary%sum_lane_self_time)

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_text_metric(buffer, openmp_metadata_key_text(metadata(i)), key_width, &
                                           openmp_metadata_value_text(metadata(i)))
         end do
      end if

      call append_openmp_line(buffer, '')
      call append_openmp_line(buffer, &
                              'Report note: lane min/avg/max fields are over participating lanes only; '// &
                              'missing lanes are not zero-filled.')
      call append_openmp_line(buffer, &
                              'Report note: missing lane counts are shown as unknown when mixed timed-region '// &
                              'epochs make the aggregate count ambiguous.')
      call append_openmp_line(buffer, &
                              'Report note: timed-region envelope time is wall-clock time, not summed lane work.')
      call append_openmp_line(buffer, '')

      name_width = openmp_summary_name_width(summary)
      missing_width = openmp_summary_missing_width(summary)
      line_width = name_width + missing_width + 220
      allocate (character(len=line_width) :: line)
      write (line, '(a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a,2x,a)') &
         padded_openmp_text('Timer name', name_width), 'Part', padded_openmp_text('Missing', missing_width), &
         'Sum Incl (s)', 'Sum Self (s)', &
         'Min Lane Incl (s)', 'Avg Lane Incl (s)', 'Max Lane Incl (s)', 'Avg Lane Self (s)', &
         'Min Calls', 'Avg Calls', 'Max Calls'
      call append_openmp_line(buffer, trim(line))
      call append_openmp_line(buffer, repeat('-', len_trim(line)))

      do i = 1, summary%num_entries
         display = repeat(' ', 2*summary%entries(i)%depth)//openmp_entry_name(summary%entries(i))
         write (line, '(a,2x,i4,2x,a,2x,f12.6,2x,f12.6,2x,f17.6,2x,f17.6,2x,f17.6,2x,f17.6,2x,i9,2x,f9.3,2x,i9)') &
            padded_openmp_text(display, name_width), summary%entries(i)%participating_lane_count, &
            padded_openmp_text(openmp_missing_lane_count_text(summary%entries(i)), missing_width), &
            summary%entries(i)%sum_lane_inclusive_time, &
            summary%entries(i)%sum_lane_self_time, summary%entries(i)%min_lane_inclusive_time, &
            summary%entries(i)%avg_lane_inclusive_time, summary%entries(i)%max_lane_inclusive_time, &
            summary%entries(i)%avg_lane_self_time, summary%entries(i)%min_lane_call_count, &
            summary%entries(i)%avg_lane_call_count, summary%entries(i)%max_lane_call_count
         call append_openmp_line(buffer, trim(line))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_openmp_summary

   integer function openmp_summary_missing_width(summary) result(width)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      integer :: i

      width = len('Missing')
      do i = 1, summary%num_entries
         width = max(width, len(openmp_missing_lane_count_text(summary%entries(i))))
      end do
   end function openmp_summary_missing_width

   function openmp_missing_lane_count_text(entry) result(text)
      type(ftimer_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      if (.not. entry%missing_lane_count_known) then
         text = 'unknown'
      else
         write (buffer, '(i0)') entry%missing_lane_count
         text = trim(buffer)
      end if
   end function openmp_missing_lane_count_text

   subroutine append_openmp_real_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      real(wp), intent(in) :: value
      character(len=64) :: value_text

      write (value_text, '(f0.6)') value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_openmp_real_metric

   subroutine append_openmp_integer_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      integer, intent(in) :: value
      character(len=32) :: value_text

      write (value_text, '(i0)') value
      call append_openmp_text_metric(buffer, label, key_width, trim(value_text))
   end subroutine append_openmp_integer_metric

   subroutine append_openmp_text_metric(buffer, label, key_width, value)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: label
      integer, intent(in) :: key_width
      character(len=*), intent(in) :: value

      call append_openmp_line(buffer, padded_openmp_text(label, key_width)//' : '//value)
   end subroutine append_openmp_text_metric

   integer function openmp_summary_name_width(summary) result(width)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, 2*summary%entries(i)%depth + len(openmp_entry_name(summary%entries(i))))
      end do
   end function openmp_summary_name_width

   function padded_openmp_text(value, width) result(text)
      character(len=*), intent(in) :: value
      integer, intent(in) :: width
      character(len=:), allocatable :: text
      integer :: copy_len

      allocate (character(len=max(width, len_trim(value))) :: text)
      text = repeat(' ', len(text))
      copy_len = min(len(text), len_trim(value))
      if (copy_len > 0) text(1:copy_len) = value(1:copy_len)
   end function padded_openmp_text

   module subroutine format_openmp_summary_csv(summary, text, metadata, include_header)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      logical, intent(in), optional :: include_header
      type(openmp_report_buffer_t) :: buffer
      integer :: i
      logical :: emit_header

      call init_openmp_report_buffer(buffer, default_report_buffer_capacity)
      emit_header = .true.
      if (present(include_header)) emit_header = include_header

      if (emit_header) call append_openmp_line(buffer, openmp_csv_header_line())
      call append_openmp_summary_csv_record(buffer, summary)
      if (present(metadata)) then
         do i = 1, size(metadata)
            if (openmp_metadata_key_len(metadata(i)) <= 0) cycle
            call append_openmp_metadata_csv_record(buffer, metadata(i))
         end do
      end if
      do i = 1, summary%num_entries
         call append_openmp_entry_csv_record(buffer, summary%entries(i))
      end do

      call finish_openmp_report_buffer(buffer, text)
   end subroutine format_openmp_summary_csv

   subroutine append_openmp_summary_csv_record(buffer, summary)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_openmp_summary_t), intent(in) :: summary
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'summary')
      call append_empty_openmp_csv_fields(row, 2)
      call append_openmp_csv_field(row, summary%start_date)
      call append_openmp_csv_field(row, summary%end_date)
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%summary_window_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%timed_region_envelope_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%sum_lane_root_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(summary%sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%configured_lane_capacity))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%observed_participating_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(summary%num_entries))
      call append_empty_openmp_csv_fields(row, 21)
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_summary_csv_record

   subroutine append_openmp_metadata_csv_record(buffer, item)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_metadata_t), intent(in) :: item
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'metadata')
      call append_openmp_csv_field(row, openmp_metadata_key_text(item))
      call append_openmp_csv_field(row, openmp_metadata_value_text(item))
      call append_empty_openmp_csv_fields(row, 30)
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_metadata_csv_record

   subroutine append_openmp_entry_csv_record(buffer, entry)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(ftimer_openmp_summary_entry_t), intent(in) :: entry
      type(openmp_report_buffer_t) :: row

      call begin_openmp_csv_row(row, 'entry')
      call append_empty_openmp_csv_fields(row, 11)
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%node_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%parent_id))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%depth))
      call append_openmp_csv_field(row, openmp_entry_name(entry))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%eligible_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%participating_lane_count))
      call append_openmp_csv_field(row, openmp_integer_csv_text(entry%missing_lane_count))
      call append_openmp_csv_field(row, openmp_logical_csv_text(entry%missing_lane_count_known))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%sum_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_lane_inclusive_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%lane_inclusive_imbalance))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%min_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%max_lane_self_time))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%lane_self_imbalance))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%min_lane_call_count))
      call append_openmp_csv_field(row, openmp_real_csv_text(entry%avg_lane_call_count))
      call append_openmp_csv_field(row, openmp_int64_csv_text(entry%max_lane_call_count))
      call append_openmp_row(buffer, row)
   end subroutine append_openmp_entry_csv_record

   subroutine begin_openmp_csv_row(row, record_type)
      type(openmp_report_buffer_t), intent(out) :: row
      character(len=*), intent(in) :: record_type

      call init_openmp_report_buffer(row, 512)
      call append_openmp_csv_field(row, FTIMER_OPENMP_CSV_FORMAT_VERSION)
      call append_openmp_csv_field(row, 'openmp')
      call append_openmp_csv_field(row, record_type)
   end subroutine begin_openmp_csv_row

   function openmp_csv_header_line() result(line)
      character(len=:), allocatable :: line
      type(openmp_report_buffer_t) :: row

      call init_openmp_report_buffer(row, 1024)
      call append_openmp_csv_field(row, 'format_version')
      call append_openmp_csv_field(row, 'summary_kind')
      call append_openmp_csv_field(row, 'record_type')
      call append_openmp_csv_field(row, 'key')
      call append_openmp_csv_field(row, 'value')
      call append_openmp_csv_field(row, 'start_date')
      call append_openmp_csv_field(row, 'end_date')
      call append_openmp_csv_field(row, 'summary_window_time')
      call append_openmp_csv_field(row, 'timed_region_envelope_time')
      call append_openmp_csv_field(row, 'sum_lane_root_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'configured_lane_capacity')
      call append_openmp_csv_field(row, 'observed_participating_lane_count')
      call append_openmp_csv_field(row, 'num_entries')
      call append_openmp_csv_field(row, 'node_id')
      call append_openmp_csv_field(row, 'parent_id')
      call append_openmp_csv_field(row, 'depth')
      call append_openmp_csv_field(row, 'name')
      call append_openmp_csv_field(row, 'eligible_lane_count')
      call append_openmp_csv_field(row, 'participating_lane_count')
      call append_openmp_csv_field(row, 'missing_lane_count')
      call append_openmp_csv_field(row, 'missing_lane_count_known')
      call append_openmp_csv_field(row, 'sum_lane_inclusive_time')
      call append_openmp_csv_field(row, 'sum_lane_self_time')
      call append_openmp_csv_field(row, 'min_lane_inclusive_time')
      call append_openmp_csv_field(row, 'avg_lane_inclusive_time')
      call append_openmp_csv_field(row, 'max_lane_inclusive_time')
      call append_openmp_csv_field(row, 'lane_inclusive_imbalance')
      call append_openmp_csv_field(row, 'min_lane_self_time')
      call append_openmp_csv_field(row, 'avg_lane_self_time')
      call append_openmp_csv_field(row, 'max_lane_self_time')
      call append_openmp_csv_field(row, 'lane_self_imbalance')
      call append_openmp_csv_field(row, 'min_lane_call_count')
      call append_openmp_csv_field(row, 'avg_lane_call_count')
      call append_openmp_csv_field(row, 'max_lane_call_count')
      call finish_openmp_report_buffer(row, line)
   end function openmp_csv_header_line

   module subroutine get_openmp_csv_header_mode(filename, append_mode, include_header, status, iomsg)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=:), allocatable :: expected_header

      expected_header = openmp_csv_header_line()
      call ftimer_get_csv_append_header_mode(filename, append_mode, include_header, status, iomsg, &
                                             expected_header, FTIMER_OPENMP_CSV_FORMAT_VERSION, &
                                             [character(len=6) :: 'openmp'], &
                                             [character(len=8) :: 'summary', 'metadata', 'entry'], &
                                             'existing OpenMP summary CSV header does not match format version 1', &
                                             'existing OpenMP summary CSV records do not match format version 1', &
                                             'existing OpenMP summary CSV records contain a bare carriage return', &
                                             'existing OpenMP summary CSV records contain malformed quoted fields', &
                                             'existing OpenMP summary CSV append target does not end with a newline', &
                                             'existing OpenMP summary CSV records contain an unterminated quoted field')
   end subroutine get_openmp_csv_header_mode

   subroutine append_empty_openmp_csv_fields(row, count)
      type(openmp_report_buffer_t), intent(inout) :: row
      integer, intent(in) :: count
      integer :: i

      do i = 1, count
         call append_openmp_csv_field(row, '')
      end do
   end subroutine append_empty_openmp_csv_fields

   subroutine append_openmp_csv_field(row, value)
      type(openmp_report_buffer_t), intent(inout) :: row
      character(len=*), intent(in) :: value
      integer :: i

      if (row%used > 0) call append_openmp_text(row, ',')
      call append_openmp_text(row, '"')
      do i = 1, len_trim(value)
         if (value(i:i) == '"') then
            call append_openmp_text(row, '""')
         else
            call append_openmp_text(row, value(i:i))
         end if
      end do
      call append_openmp_text(row, '"')
   end subroutine append_openmp_csv_field

   subroutine append_openmp_row(buffer, row)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      type(openmp_report_buffer_t), intent(in) :: row

      if (row%used > 0) call append_openmp_text(buffer, row%chars(1:row%used))
      call append_openmp_text(buffer, new_line('a'))
   end subroutine append_openmp_row

   function openmp_integer_csv_text(value) result(text)
      integer, intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function openmp_integer_csv_text

   function openmp_int64_csv_text(value) result(text)
      integer(int64), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      text = trim(buffer)
   end function openmp_int64_csv_text

   function openmp_real_csv_text(value) result(text)
      real(wp), intent(in) :: value
      character(len=:), allocatable :: text
      character(len=48) :: buffer

      write (buffer, '(es32.17e4)') value
      text = trim(adjustl(buffer))
   end function openmp_real_csv_text

   function openmp_logical_csv_text(value) result(text)
      logical, intent(in) :: value
      character(len=:), allocatable :: text

      if (value) then
         text = 'true'
      else
         text = 'false'
      end if
   end function openmp_logical_csv_text

   module subroutine write_text_block(unit, text, io, iomsg)
      integer, intent(in) :: unit
      character(len=*), intent(in) :: text
      integer, intent(out) :: io
      character(len=*), intent(out) :: iomsg
      integer :: start
      integer :: line_end

      io = 0
      iomsg = ''
      start = 1
      do
         if (start > len(text)) exit
         line_end = index(text(start:), new_line('a'))
         if (line_end == 0) then
            write (unit, '(a)', iostat=io, iomsg=iomsg) text(start:)
            exit
         else
            line_end = start + line_end - 2
            if (line_end >= start) then
               write (unit, '(a)', iostat=io, iomsg=iomsg) text(start:line_end)
            else
               write (unit, '(a)', iostat=io, iomsg=iomsg) ''
            end if
            if (io /= 0) exit
            start = line_end + 2
         end if
      end do
   end subroutine write_text_block

   subroutine append_openmp_line(buffer, line)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: line

      call append_openmp_text(buffer, trim(line))
      call append_openmp_text(buffer, new_line('a'))
   end subroutine append_openmp_line

   subroutine init_openmp_report_buffer(buffer, initial_capacity)
      type(openmp_report_buffer_t), intent(out) :: buffer
      integer, intent(in) :: initial_capacity
      integer :: capacity

      capacity = max(1, initial_capacity)
      allocate (character(len=capacity) :: buffer%chars)
      buffer%used = 0
   end subroutine init_openmp_report_buffer

   subroutine append_openmp_text(buffer, fragment)
      type(openmp_report_buffer_t), intent(inout) :: buffer
      character(len=*), intent(in) :: fragment
      integer :: fragment_len
      integer :: next_used

      fragment_len = len(fragment)
      if (fragment_len <= 0) return

      next_used = buffer%used + fragment_len
      call ensure_openmp_report_capacity(buffer, next_used)
      buffer%chars(buffer%used + 1:next_used) = fragment
      buffer%used = next_used
   end subroutine append_openmp_text

   subroutine finish_openmp_report_buffer(buffer, text)
      type(openmp_report_buffer_t), intent(in) :: buffer
      character(len=:), allocatable, intent(out) :: text

      if (buffer%used > 0) then
         text = buffer%chars(1:buffer%used)
      else
         text = ''
      end if
   end subroutine finish_openmp_report_buffer

   subroutine ensure_openmp_report_capacity(buffer, required_capacity)
      type(openmp_report_buffer_t), intent(inout) :: buffer
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
   end subroutine ensure_openmp_report_capacity

   integer function openmp_metadata_key_width(metadata) result(width)
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer :: i

      width = 0
      if (.not. present(metadata)) return
      do i = 1, size(metadata)
         width = max(width, len(openmp_metadata_key_text(metadata(i))))
      end do
   end function openmp_metadata_key_width

   integer function openmp_metadata_key_len(item) result(key_len)
      type(ftimer_metadata_t), intent(in) :: item

      if (allocated(item%key)) then
         key_len = len_trim(item%key)
      else
         key_len = 0
      end if
   end function openmp_metadata_key_len

   function openmp_metadata_key_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%key)) then
         text = trim(item%key)
      else
         text = ''
      end if
   end function openmp_metadata_key_text

   function openmp_metadata_value_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      if (allocated(item%value)) then
         text = trim(item%value)
      else
         text = ''
      end if
   end function openmp_metadata_value_text

   function openmp_entry_name(entry) result(name)
      type(ftimer_openmp_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = '<unnamed>'
      end if
   end function openmp_entry_name

end submodule ftimer_openmp_reports
