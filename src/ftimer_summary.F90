module ftimer_summary
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: ftimer_call_stack_t, ftimer_metadata_t, ftimer_mpi_summary_entry_t, &
                           ftimer_mpi_summary_t, ftimer_mpi_union_summary_entry_t, &
                           ftimer_mpi_union_summary_t, ftimer_segment_t, ftimer_summary_entry_t, &
                           ftimer_summary_t, wp
   implicit none
   private

   public :: build_summary
   public :: format_summary
   public :: format_mpi_summary
   public :: format_mpi_union_summary
   public :: ftimer_summary_status

contains

   subroutine build_summary(summary, segments, init_wtime, init_date, end_time, end_date)
      type(ftimer_summary_t), intent(out) :: summary
      type(ftimer_segment_t), intent(in), optional :: segments(:)
      real(wp), intent(in) :: init_wtime
      real(wp), intent(in) :: end_time
      character(len=*), intent(in) :: init_date
      character(len=*), intent(in) :: end_date

      call clear_summary(summary)
      summary%start_date = init_date
      summary%end_date = end_date
      summary%total_time = end_time - init_wtime

      if (present(segments)) then
         call populate_context_cardinality(summary, segments)
         call populate_summary_entries(summary%entries, summary%num_entries, &
                                       segments, summary%total_time, end_time)
      else
         summary%num_entries = 0
         allocate (summary%entries(0))
         summary%num_context_diagnostics = 0
         allocate (summary%context_diagnostics(0))
      end if
      summary%has_active_timers = summary_has_active_entries(summary)
      if (summary%num_entries <= 0) return
   end subroutine build_summary

   subroutine format_summary(summary, text, metadata)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      character(len=64) :: fmt
      character(len=:), allocatable :: header_suffix
      character(len=:), allocatable :: line
      character(len=:), allocatable :: padded
      character(len=8) :: active_value
      integer :: call_width
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width
      logical :: has_active_entries

      text = ''
      has_active_entries = summary_has_active_entries(summary)
      key_width = metadata_key_width(metadata)
      key_width = max(key_width, len('Active timers'))
      name_width = summary_name_width(summary)
      call_width = summary_call_count_width(summary)
      line_width = summary_line_width(name_width, has_active_entries, call_width)
      allocate (character(len=line_width) :: line)

      write (line, '(f0.6)') summary%total_time
      call set_padded_text(padded, 'Total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(line))

      if (has_active_entries) then
         active_value = 'yes'
         call set_padded_text(padded, 'Active timers', key_width)
         call append_line(text, padded(1:key_width)//' : '//trim(active_value))
         call append_line(text, 'Snapshot note : active timers are included through the snapshot timestamp.')
      end if

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            if (has_active_entries .and. metadata_key_is_reserved(metadata_key_text(metadata(i)))) cycle
            call set_padded_text(padded, metadata_key_display_text(metadata(i)), key_width)
            call append_line(text, padded(1:key_width)//' : '//metadata_value_display_text(metadata(i)))
         end do
      end if

      call append_line(text, '')
      call set_padded_text(padded, 'Timer name', name_width)
      line = repeat(' ', len(line))
      header_suffix = summary_header_suffix(has_active_entries, call_width)
      if (has_active_entries) then
         line(1:name_width + len(header_suffix)) = padded(1:name_width)//header_suffix
      else
         line(1:name_width + len(header_suffix)) = padded(1:name_width)//header_suffix
      end if
      call append_line(text, trim(line))
      call append_line(text, repeat('-', len_trim(line)))

      if (has_active_entries) then
         write (fmt, '("(a",i0,",2x,f12.6,2x,f12.6,2x,i",i0,",2x,f8.2,2x,a)")') &
            name_width, call_width
         do i = 1, summary%num_entries
            call set_padded_text(padded, display_name(summary%entries(i)), name_width)
            write (line, fmt) padded(1:name_width), summary%entries(i)%inclusive_time, &
               summary%entries(i)%self_time, summary%entries(i)%call_count, summary%entries(i)%pct_time, &
               active_text(summary%entries(i)%is_active)
            call append_line(text, trim(line))
         end do
      else
         write (fmt, '("(a",i0,",2x,f12.6,2x,f12.6,2x,i",i0,",2x,f8.2)")') &
            name_width, call_width
         do i = 1, summary%num_entries
            call set_padded_text(padded, display_name(summary%entries(i)), name_width)
            write (line, fmt) padded(1:name_width), summary%entries(i)%inclusive_time, &
               summary%entries(i)%self_time, summary%entries(i)%call_count, summary%entries(i)%pct_time
            call append_line(text, trim(line))
         end do
      end if
   end subroutine format_summary

   subroutine format_mpi_summary(summary, text, metadata)
      type(ftimer_mpi_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      character(len=128) :: fmt
      character(len=:), allocatable :: header_suffix
      character(len=64) :: value_line
      character(len=:), allocatable :: line
      character(len=:), allocatable :: padded
      integer :: avg_call_width
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      text = ''
      key_width = metadata_key_width(metadata)
      key_width = max(key_width, len('MPI ranks'))
      key_width = max(key_width, len('Min total time (s)'))
      key_width = max(key_width, len('Avg total time (s)'))
      key_width = max(key_width, len('Max total time (s)'))
      key_width = max(key_width, len('Min total rank'))
      key_width = max(key_width, len('Max total rank'))
      key_width = max(key_width, len('Total imbalance'))

      call set_padded_text(padded, 'MPI ranks', key_width)
      write (value_line, '(i0)') summary%num_ranks
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%min_total_time
      call set_padded_text(padded, 'Min total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%avg_total_time
      call set_padded_text(padded, 'Avg total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%max_total_time
      call set_padded_text(padded, 'Max total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(i0)') summary%min_total_time_rank
      call set_padded_text(padded, 'Min total rank', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(i0)') summary%max_total_time_rank
      call set_padded_text(padded, 'Max total rank', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%total_time_imbalance
      call set_padded_text(padded, 'Total imbalance', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            call set_padded_text(padded, metadata_key_display_text(metadata(i)), key_width)
            call append_line(text, padded(1:key_width)//' : '//metadata_value_display_text(metadata(i)))
         end do
      end if

      call append_line(text, '')
      call append_line(text, 'Report note: per-entry table is an abbreviated view of ftimer_mpi_summary_t; '// &
                       'use mpi_summary() for all min/max self, call, percent, and tree fields.')
      call append_line(text, 'Avg % is the arithmetic mean of rank-local % Total values, '// &
                       'not 100*Avg Incl/Avg total time.')

      call append_line(text, '')
      name_width = mpi_summary_name_width(summary)
      avg_call_width = mpi_avg_call_count_width(summary)
      line_width = mpi_summary_line_width(name_width, avg_call_width)
      allocate (character(len=line_width) :: line)

      call set_padded_text(padded, 'Timer name', name_width)
      line = repeat(' ', len(line))
      header_suffix = mpi_header_suffix(avg_call_width)
      line(1:name_width + len(header_suffix)) = padded(1:name_width)//header_suffix
      call append_line(text, trim(line))
      call append_line(text, repeat('-', len_trim(line)))

      write (fmt, '("(a",i0,",2x,f12.6,2x,i8,2x,f12.6,2x,f12.6,2x,i8,2x,f6.3,2x,f12.6,2x,f",i0,".3,2x,f8.2)")') &
         name_width, avg_call_width
      do i = 1, summary%num_entries
         call set_padded_text(padded, display_mpi_name(summary%entries(i)), name_width)
         write (line, fmt) padded(1:name_width), summary%entries(i)%min_inclusive_time, &
            summary%entries(i)%min_inclusive_time_rank, summary%entries(i)%avg_inclusive_time, &
            summary%entries(i)%max_inclusive_time, summary%entries(i)%max_inclusive_time_rank, &
            summary%entries(i)%inclusive_imbalance, summary%entries(i)%avg_self_time, &
            summary%entries(i)%avg_call_count, summary%entries(i)%avg_pct_time
         call append_line(text, trim(line))
      end do
   end subroutine format_mpi_summary

   subroutine format_mpi_union_summary(summary, text, metadata)
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      character(len=128) :: fmt
      character(len=:), allocatable :: header_suffix
      character(len=64) :: value_line
      character(len=:), allocatable :: line
      character(len=:), allocatable :: padded
      integer :: avg_call_width
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: missing_rank_count
      integer :: name_width

      text = ''
      call append_line(text, 'Sparse MPI union summary')

      key_width = metadata_key_width(metadata)
      key_width = max(key_width, len('MPI ranks'))
      key_width = max(key_width, len('Min total time (s)'))
      key_width = max(key_width, len('Avg total time (s)'))
      key_width = max(key_width, len('Max total time (s)'))
      key_width = max(key_width, len('Min total rank'))
      key_width = max(key_width, len('Max total rank'))
      key_width = max(key_width, len('Total imbalance'))

      call set_padded_text(padded, 'MPI ranks', key_width)
      write (value_line, '(i0)') summary%num_ranks
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%min_total_time
      call set_padded_text(padded, 'Min total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%avg_total_time
      call set_padded_text(padded, 'Avg total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%max_total_time
      call set_padded_text(padded, 'Max total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(i0)') summary%min_total_time_rank
      call set_padded_text(padded, 'Min total rank', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(i0)') summary%max_total_time_rank
      call set_padded_text(padded, 'Max total rank', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      write (value_line, '(f0.6)') summary%total_time_imbalance
      call set_padded_text(padded, 'Total imbalance', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(value_line))

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (metadata_key_len(metadata(i)) <= 0) cycle
            call set_padded_text(padded, metadata_key_display_text(metadata(i)), key_width)
            call append_line(text, padded(1:key_width)//' : '//metadata_value_display_text(metadata(i)))
         end do
      end if

      call append_line(text, '')
      call append_line(text, 'Report note: sparse entry min/avg/max fields are over participating ranks only; '// &
                       'missing ranks are not zero-filled.')
      call append_line(text, 'Missing ranks = MPI ranks - Participating; absent ranks do not contribute '// &
                       'zero-call or zero-time samples.')
      call append_line(text, 'Avg % is the arithmetic mean of participating rank-local % Total values, '// &
                       'not 100*Avg Incl/Avg total time.')

      call append_line(text, '')
      name_width = mpi_union_summary_name_width(summary)
      avg_call_width = mpi_union_avg_call_count_width(summary)
      line_width = mpi_union_summary_line_width(name_width, avg_call_width)
      allocate (character(len=line_width) :: line)

      call set_padded_text(padded, 'Timer name', name_width)
      line = repeat(' ', len(line))
      header_suffix = mpi_union_header_suffix(avg_call_width)
      line(1:name_width + len(header_suffix)) = padded(1:name_width)//header_suffix
      call append_line(text, trim(line))
      call append_line(text, repeat('-', len_trim(line)))

      write (fmt, '("(a",i0,",2x,i13,2x,i7,2x,f12.6,2x,i8,2x,f12.6,2x,f12.6,2x,i8,2x,f6.3,2x,f12.6,2x,f",i0,".3,2x,f8.2)")') &
         name_width, avg_call_width
      do i = 1, summary%num_entries
         call set_padded_text(padded, display_mpi_union_name(summary%entries(i)), name_width)
         missing_rank_count = summary%num_ranks - summary%entries(i)%participating_rank_count
         write (line, fmt) padded(1:name_width), summary%entries(i)%participating_rank_count, missing_rank_count, &
            summary%entries(i)%min_inclusive_time, summary%entries(i)%min_inclusive_time_rank, &
            summary%entries(i)%avg_inclusive_time, summary%entries(i)%max_inclusive_time, &
            summary%entries(i)%max_inclusive_time_rank, summary%entries(i)%inclusive_imbalance, &
            summary%entries(i)%avg_self_time, summary%entries(i)%avg_call_count, summary%entries(i)%avg_pct_time
         call append_line(text, trim(line))
      end do
   end subroutine format_mpi_union_summary

   function ftimer_summary_status(summary) result(status)
      type(ftimer_summary_t), intent(in) :: summary
      integer :: status

      status = summary%num_entries
   end function ftimer_summary_status

   subroutine append_line(text, line)
      character(len=:), allocatable, intent(inout) :: text
      character(len=*), intent(in) :: line

      text = text//trim(line)//new_line('a')
   end subroutine append_line

   subroutine clear_summary(summary)
      type(ftimer_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      if (allocated(summary%context_diagnostics)) deallocate (summary%context_diagnostics)
      summary%start_date = ''
      summary%end_date = ''
      summary%total_time = 0.0_wp
      summary%num_entries = 0
      summary%has_active_timers = .false.
      summary%total_contexts = 0
      summary%max_contexts_per_timer = 0
      summary%num_context_diagnostics = 0
   end subroutine clear_summary

   subroutine populate_context_cardinality(summary, segments)
      type(ftimer_summary_t), intent(inout) :: summary
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer :: context_count
      integer :: i

      summary%total_contexts = 0
      summary%max_contexts_per_timer = 0
      summary%num_context_diagnostics = size(segments)
      allocate (summary%context_diagnostics(summary%num_context_diagnostics))
      do i = 1, size(segments)
         context_count = segments(i)%contexts%count
         summary%total_contexts = summary%total_contexts + context_count
         summary%max_contexts_per_timer = max(summary%max_contexts_per_timer, context_count)
         summary%context_diagnostics(i)%name = segments(i)%name
         summary%context_diagnostics(i)%context_count = context_count
      end do
   end subroutine populate_context_cardinality

   subroutine populate_summary_entries(entries, num_entries, segments, total_time, end_time)
      type(ftimer_summary_entry_t), allocatable, intent(out) :: entries(:)
      integer, intent(out) :: num_entries
      type(ftimer_segment_t), intent(in) :: segments(:)
      real(wp), intent(in) :: total_time
      real(wp), intent(in) :: end_time
      integer, allocatable :: child_sum_entry(:)
      integer, allocatable :: entry_stack(:)
      integer, allocatable :: included_order(:)
      integer(int64), allocatable :: node_call_count(:)
      integer, allocatable :: node_ctx(:)
      integer, allocatable :: node_depth(:)
      integer, allocatable :: node_segment(:)
      integer, allocatable :: sort_work(:)
      integer, allocatable :: sorted_nodes(:)
      integer :: ctx
      integer :: i
      integer :: node
      integer :: position
      integer :: stack_size
      integer :: visible_count
      real(wp), allocatable :: child_sum(:)
      real(wp), allocatable :: node_inclusive(:)

      visible_count = 0
      do i = 1, size(segments)
         do ctx = 1, segments(i)%contexts%count
            if (.not. context_is_visible(segments(i), ctx, end_time)) cycle
            visible_count = visible_count + 1
         end do
      end do

      allocate (entries(visible_count))
      num_entries = 0
      if (visible_count <= 0) return

      allocate (included_order(visible_count))
      allocate (node_call_count(visible_count))
      allocate (node_ctx(visible_count))
      allocate (node_depth(visible_count))
      allocate (node_inclusive(visible_count))
      allocate (node_segment(visible_count))
      allocate (sorted_nodes(visible_count))
      allocate (sort_work(visible_count))

      node = 0
      do i = 1, size(segments)
         do ctx = 1, segments(i)%contexts%count
            if (.not. context_is_visible(segments(i), ctx, end_time)) cycle
            node = node + 1
            node_segment(node) = i
            node_ctx(node) = ctx
            node_depth(node) = segments(i)%contexts%stacks(ctx)%depth
            node_inclusive(node) = inclusive_for_context(segments(i), ctx, end_time)
            node_call_count(node) = call_count_for_context(segments(i), ctx)
            sorted_nodes(node) = node
         end do
      end do

      call sort_visible_nodes(sorted_nodes, sort_work, segments, node_segment, node_ctx)

      allocate (entry_stack(visible_count))
      stack_size = 0
      do i = 1, visible_count
         node = sorted_nodes(i)
         call unwind_summary_stack(stack_size, node_depth(node))
         if (.not. node_is_rooted(node, stack_size, entry_stack, segments, &
                                  node_segment, node_ctx)) cycle

         num_entries = num_entries + 1
         included_order(num_entries) = node
         stack_size = stack_size + 1
         entry_stack(stack_size) = node
      end do

      if (num_entries <= 0) then
         deallocate (entries)
         allocate (entries(0))
         return
      end if

      if (num_entries < visible_count) then
         deallocate (entries)
         allocate (entries(num_entries))
      end if

      allocate (child_sum(num_entries))
      allocate (child_sum_entry(num_entries))
      position = 0
      stack_size = 0
      child_sum = 0.0_wp
      do i = 1, num_entries
         node = included_order(i)
         call finalize_completed_entries(entries, child_sum_entry, child_sum, &
                                         stack_size, node_depth(node))

         position = position + 1
         entries(position)%name = segments(node_segment(node))%name
         entries(position)%depth = node_depth(node)
         entries(position)%node_id = position
         entries(position)%inclusive_time = node_inclusive(node)
         entries(position)%call_count = node_call_count(node)
         entries(position)%is_active = context_is_active(segments(node_segment(node)), node_ctx(node))
         entries(position)%timer_context_count = segments(node_segment(node))%contexts%count
         if (entries(position)%call_count > 0) then
            entries(position)%avg_time = entries(position)%inclusive_time/ &
                                         real(entries(position)%call_count, wp)
         else
            entries(position)%avg_time = 0.0_wp
         end if
         if (total_time > 0.0_wp) then
            entries(position)%pct_time = 100.0_wp*entries(position)%inclusive_time/total_time
         else
            entries(position)%pct_time = 0.0_wp
         end if

         if (stack_size > 0) then
            entries(position)%parent_id = child_sum_entry(stack_size)
            child_sum(stack_size) = child_sum(stack_size) + entries(position)%inclusive_time
         else
            entries(position)%parent_id = 0
         end if
         stack_size = stack_size + 1
         child_sum_entry(stack_size) = position
         child_sum(stack_size) = 0.0_wp
      end do

      call finalize_completed_entries(entries, child_sum_entry, child_sum, stack_size, -1)
   end subroutine populate_summary_entries

   recursive subroutine sort_visible_nodes(order, work, segments, node_segment, node_ctx)
      integer, intent(inout) :: order(:)
      integer, intent(inout) :: work(:)
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)

      call merge_sort_nodes(order, work, 1, size(order), segments, node_segment, node_ctx)
   end subroutine sort_visible_nodes

   recursive subroutine merge_sort_nodes(order, work, left, right, segments, node_segment, node_ctx)
      integer, intent(inout) :: order(:)
      integer, intent(inout) :: work(:)
      integer, intent(in) :: left
      integer, intent(in) :: right
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer :: mid

      if (left >= right) return
      mid = (left + right)/2
      call merge_sort_nodes(order, work, left, mid, segments, node_segment, node_ctx)
      call merge_sort_nodes(order, work, mid + 1, right, segments, node_segment, node_ctx)
      call merge_node_runs(order, work, left, mid, right, segments, node_segment, node_ctx)
   end subroutine merge_sort_nodes

   subroutine merge_node_runs(order, work, left, mid, right, segments, node_segment, node_ctx)
      integer, intent(inout) :: order(:)
      integer, intent(inout) :: work(:)
      integer, intent(in) :: left
      integer, intent(in) :: mid
      integer, intent(in) :: right
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer :: i
      integer :: j
      integer :: k

      i = left
      j = mid + 1
      k = left
      do while ((i <= mid) .and. (j <= right))
         if (node_path_precedes(order(i), order(j), segments, node_segment, node_ctx)) then
            work(k) = order(i)
            i = i + 1
         else
            work(k) = order(j)
            j = j + 1
         end if
         k = k + 1
      end do

      do while (i <= mid)
         work(k) = order(i)
         i = i + 1
         k = k + 1
      end do

      do while (j <= right)
         work(k) = order(j)
         j = j + 1
         k = k + 1
      end do

      order(left:right) = work(left:right)
   end subroutine merge_node_runs

   logical function node_path_precedes(lhs, rhs, segments, node_segment, node_ctx) result(precedes)
      integer, intent(in) :: lhs
      integer, intent(in) :: rhs
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer :: lhs_len
      integer :: rhs_len
      integer :: pos
      integer :: lhs_part
      integer :: rhs_part

      lhs_len = node_path_length(segments, node_segment, node_ctx, lhs)
      rhs_len = node_path_length(segments, node_segment, node_ctx, rhs)
      do pos = 1, min(lhs_len, rhs_len)
         lhs_part = node_path_component(segments, node_segment, node_ctx, lhs, pos)
         rhs_part = node_path_component(segments, node_segment, node_ctx, rhs, pos)
         if (lhs_part < rhs_part) then
            precedes = .true.
            return
         else if (lhs_part > rhs_part) then
            precedes = .false.
            return
         end if
      end do

      precedes = lhs_len <= rhs_len
   end function node_path_precedes

   integer function node_path_length(segments, node_segment, node_ctx, node) result(path_length)
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer, intent(in) :: node

      path_length = segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth + 1
   end function node_path_length

   integer function node_path_component(segments, node_segment, node_ctx, node, &
                                        position) result(component)
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer, intent(in) :: node
      integer, intent(in) :: position
      if (position <= segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth) then
         component = segments(node_segment(node))%contexts%stacks(node_ctx(node))%ids(position)
      else
         component = node_segment(node)
      end if
   end function node_path_component

   subroutine unwind_summary_stack(stack_size, target_depth)
      integer, intent(inout) :: stack_size
      integer, intent(in) :: target_depth

      do while (stack_size > target_depth)
         stack_size = stack_size - 1
      end do
   end subroutine unwind_summary_stack

   logical function node_is_rooted(node, stack_size, stack_nodes, segments, &
                                   node_segment, node_ctx) result(is_rooted)
      integer, intent(in) :: node
      integer, intent(in) :: stack_size
      integer, intent(in) :: stack_nodes(:)
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_ctx(:)
      integer :: parent_node

      if (segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth == 0) then
         is_rooted = .true.
         return
      end if

      is_rooted = .false.
      if (stack_size /= segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth) return

      parent_node = stack_nodes(stack_size)
      if (segments(node_segment(parent_node))%contexts%stacks(node_ctx(parent_node))%depth /= &
          segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth - 1) return
      if (node_segment(parent_node) /= &
          segments(node_segment(node))%contexts%stacks(node_ctx(node))%ids( &
          segments(node_segment(node))%contexts%stacks(node_ctx(node))%depth)) return
      if (segments(node_segment(parent_node))%contexts%stacks(node_ctx(parent_node))%depth <= 0) then
         is_rooted = .true.
      else
         is_rooted = all(segments(node_segment(parent_node))%contexts%stacks(node_ctx(parent_node))%ids( &
                         1:segments(node_segment(parent_node))%contexts%stacks(node_ctx(parent_node))%depth) == &
                         segments(node_segment(node))%contexts%stacks(node_ctx(node))%ids( &
                         1:segments(node_segment(parent_node))%contexts%stacks(node_ctx(parent_node))%depth))
      end if
   end function node_is_rooted

   subroutine finalize_completed_entries(entries, child_sum_entry, child_sum, &
                                         stack_size, target_depth)
      type(ftimer_summary_entry_t), intent(inout) :: entries(:)
      integer, intent(in) :: child_sum_entry(:)
      real(wp), intent(in) :: child_sum(:)
      integer, intent(inout) :: stack_size
      integer, intent(in) :: target_depth
      integer :: entry_idx

      do while (stack_size > max(target_depth, 0))
         entry_idx = child_sum_entry(stack_size)
         entries(entry_idx)%self_time = clamp_self_time(entries(entry_idx)%inclusive_time - &
                                                        child_sum(stack_size), entries(entry_idx)%inclusive_time)
         stack_size = stack_size - 1
      end do
   end subroutine finalize_completed_entries

   function display_name(entry) result(name)
      type(ftimer_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name
      character(len=:), allocatable :: escaped_name

      escaped_name = escaped_summary_name(summary_entry_name(entry))
      name = repeat(' ', 2*entry%depth)//escaped_name
   end function display_name

   real(wp) function clamp_self_time(self_time, inclusive_time) result(clamped)
      real(wp), intent(in) :: self_time
      real(wp), intent(in) :: inclusive_time
      real(wp) :: tolerance

      clamped = self_time
      tolerance = 100.0_wp*epsilon(1.0_wp)*max(1.0_wp, abs(inclusive_time))
      if ((clamped < 0.0_wp) .and. (abs(clamped) <= tolerance)) clamped = 0.0_wp
   end function clamp_self_time

   integer(int64) function call_count_for_context(segment, ctx) result(count)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx

      count = 0_int64
      if (.not. allocated(segment%call_count)) return
      if (ctx > size(segment%call_count)) return
      count = segment%call_count(ctx)
   end function call_count_for_context

   logical function context_is_active(segment, ctx) result(is_active)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx

      is_active = .false.
      if (.not. allocated(segment%is_running)) return
      if (ctx > size(segment%is_running)) return
      is_active = segment%is_running(ctx)
   end function context_is_active

   real(wp) function inclusive_for_context(segment, ctx, end_time) result(total)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx
      real(wp), intent(in) :: end_time

      total = 0.0_wp
      if (allocated(segment%time)) then
         if (ctx <= size(segment%time)) total = segment%time(ctx)
      end if

      if (allocated(segment%is_running) .and. allocated(segment%start_time)) then
         if ((ctx <= size(segment%is_running)) .and. (ctx <= size(segment%start_time))) then
            if (segment%is_running(ctx)) total = total + end_time - segment%start_time(ctx)
         end if
      end if
   end function inclusive_for_context

   logical function context_is_visible(segment, ctx, end_time) result(is_visible)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx
      real(wp), intent(in) :: end_time

      is_visible = .false.
      if (ctx <= 0) return

      if (allocated(segment%call_count)) then
         if (ctx <= size(segment%call_count)) is_visible = segment%call_count(ctx) > 0
      end if
      if (is_visible) return

      if (allocated(segment%time)) then
         if (ctx <= size(segment%time)) is_visible = abs(segment%time(ctx)) > 0.0_wp
      end if
      if (is_visible) return

      if (allocated(segment%is_running) .and. allocated(segment%start_time)) then
         if ((ctx <= size(segment%is_running)) .and. (ctx <= size(segment%start_time))) then
            if (segment%is_running(ctx)) is_visible = .true.
         end if
      end if
   end function context_is_visible

   logical function summary_has_active_entries(summary) result(has_active)
      type(ftimer_summary_t), intent(in) :: summary
      integer :: i

      has_active = .false.
      do i = 1, summary%num_entries
         if (summary%entries(i)%is_active) then
            has_active = .true.
            return
         end if
      end do
   end function summary_has_active_entries

   function active_text(is_active) result(text)
      logical, intent(in) :: is_active
      character(len=3) :: text

      if (is_active) then
         text = 'yes'
      else
         text = 'no'
      end if
   end function active_text

   integer function metadata_key_width(metadata) result(width)
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer :: i

      width = len('Total time (s)')
      if (.not. present(metadata)) return

      do i = 1, size(metadata)
         if (metadata_key_len(metadata(i)) <= 0) cycle
         width = max(width, metadata_key_display_len(metadata(i)))
      end do
   end function metadata_key_width

   logical function metadata_key_is_reserved(key) result(is_reserved)
      character(len=*), intent(in) :: key

      is_reserved = trim(key) == 'Active timers'
   end function metadata_key_is_reserved

   subroutine set_padded_text(padded, text, width)
      character(len=:), allocatable, intent(out) :: padded
      character(len=*), intent(in) :: text
      integer, intent(in) :: width
      integer :: copy_len

      allocate (character(len=width) :: padded)
      padded = repeat(' ', width)
      copy_len = min(width, len_trim(text))
      if (copy_len > 0) padded(1:copy_len) = text(1:copy_len)
   end subroutine set_padded_text

   subroutine set_right_padded_text(padded, text, width)
      character(len=:), allocatable, intent(out) :: padded
      character(len=*), intent(in) :: text
      integer, intent(in) :: width
      integer :: copy_len
      integer :: offset

      allocate (character(len=width) :: padded)
      padded = repeat(' ', width)
      copy_len = min(width, len_trim(text))
      if (copy_len <= 0) return

      offset = width - copy_len
      padded(offset + 1:width) = text(1:copy_len)
   end subroutine set_right_padded_text

   integer function summary_line_width(name_width, show_active, call_width) result(width)
      integer, intent(in) :: name_width
      integer, intent(in) :: call_width
      logical, intent(in) :: show_active

      if (show_active) then
         width = name_width + 56 + max(0, call_width - 8)
      else
         width = name_width + 48 + max(0, call_width - 8)
      end if
   end function summary_line_width

   integer function mpi_summary_line_width(name_width, avg_call_width) result(width)
      integer, intent(in) :: name_width
      integer, intent(in) :: avg_call_width

      width = name_width + 117 + max(0, avg_call_width - 10)
   end function mpi_summary_line_width

   integer function mpi_union_summary_line_width(name_width, avg_call_width) result(width)
      integer, intent(in) :: name_width
      integer, intent(in) :: avg_call_width

      width = name_width + 160 + max(0, avg_call_width - 10)
   end function mpi_union_summary_line_width

   function summary_header_suffix(show_active, call_width) result(suffix)
      logical, intent(in) :: show_active
      integer, intent(in) :: call_width
      character(len=:), allocatable :: suffix
      character(len=:), allocatable :: call_header

      if (show_active) then
         if (call_width == 8) then
            suffix = '  Inclusive (s)     Self (s)    Calls   % Total  Active'
            return
         end if

         call set_right_padded_text(call_header, 'Calls', call_width)
         suffix = '  Inclusive (s)     Self (s)  '//call_header//'  % Total  Active'
      else
         if (call_width == 8) then
            suffix = '  Inclusive (s)     Self (s)    Calls   % Total'
            return
         end if

         call set_right_padded_text(call_header, 'Calls', call_width)
         suffix = '  Inclusive (s)     Self (s)  '//call_header//'  % Total'
      end if
   end function summary_header_suffix

   function mpi_header_suffix(avg_call_width) result(suffix)
      integer, intent(in) :: avg_call_width
      character(len=:), allocatable :: suffix
      character(len=:), allocatable :: avg_call_header

      if (avg_call_width == 10) then
         suffix = '  Min Incl (s)  Min Rank  Avg Incl (s)  Max Incl (s)  Max Rank'// &
                  '   Imb.  Avg Self (s)    Avg Calls    Avg %'
         return
      end if

      call set_right_padded_text(avg_call_header, 'Avg Calls', avg_call_width)
      suffix = '  Min Incl (s)  Min Rank  Avg Incl (s)  Max Incl (s)  Max Rank'// &
               '   Imb.  Avg Self (s)  '//avg_call_header//'  Avg %'
   end function mpi_header_suffix

   function mpi_union_header_suffix(avg_call_width) result(suffix)
      integer, intent(in) :: avg_call_width
      character(len=:), allocatable :: suffix
      character(len=:), allocatable :: avg_call_header

      if (avg_call_width == 10) then
         suffix = '  Participating  Missing  Min Incl (s)  Min Rank  Avg Incl (s)'// &
                  '  Max Incl (s)  Max Rank   Imb.  Avg Self (s)    Avg Calls    Avg %'
         return
      end if

      call set_right_padded_text(avg_call_header, 'Avg Calls', avg_call_width)
      suffix = '  Participating  Missing  Min Incl (s)  Min Rank  Avg Incl (s)'// &
               '  Max Incl (s)  Max Rank   Imb.  Avg Self (s)  '//avg_call_header//'  Avg %'
   end function mpi_union_header_suffix

   integer function summary_call_count_width(summary) result(width)
      type(ftimer_summary_t), intent(in) :: summary
      integer :: i

      width = 8
      do i = 1, summary%num_entries
         width = max(width, int64_text_width(summary%entries(i)%call_count))
      end do
   end function summary_call_count_width

   integer function mpi_avg_call_count_width(summary) result(width)
      type(ftimer_mpi_summary_t), intent(in) :: summary
      integer :: i

      width = 10
      do i = 1, summary%num_entries
         width = max(width, real_fixed_text_width(summary%entries(i)%avg_call_count, 3))
      end do
   end function mpi_avg_call_count_width

   integer function mpi_union_avg_call_count_width(summary) result(width)
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      integer :: i

      width = 10
      do i = 1, summary%num_entries
         width = max(width, real_fixed_text_width(summary%entries(i)%avg_call_count, 3))
      end do
   end function mpi_union_avg_call_count_width

   integer function int64_text_width(value) result(width)
      integer(int64), intent(in) :: value
      character(len=32) :: buffer

      write (buffer, '(i0)') value
      width = len_trim(buffer)
   end function int64_text_width

   integer function real_fixed_text_width(value, decimals) result(width)
      real(wp), intent(in) :: value
      integer, intent(in) :: decimals
      character(len=16) :: fmt
      character(len=64) :: buffer

      write (fmt, '("(f0.",i0,")")') decimals
      write (buffer, fmt) value
      width = len_trim(buffer)
   end function real_fixed_text_width

   integer function summary_name_width(summary) result(width)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable :: name
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         name = display_name(summary%entries(i))
         width = max(width, len(name))
      end do
   end function summary_name_width

   integer function mpi_summary_name_width(summary) result(width)
      type(ftimer_mpi_summary_t), intent(in) :: summary
      character(len=:), allocatable :: name
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         name = display_mpi_name(summary%entries(i))
         width = max(width, len(name))
      end do
   end function mpi_summary_name_width

   integer function mpi_union_summary_name_width(summary) result(width)
      type(ftimer_mpi_union_summary_t), intent(in) :: summary
      character(len=:), allocatable :: name
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         name = display_mpi_union_name(summary%entries(i))
         width = max(width, len(name))
      end do
   end function mpi_union_summary_name_width

   function display_mpi_name(entry) result(name)
      type(ftimer_mpi_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name
      character(len=:), allocatable :: escaped_name

      escaped_name = escaped_summary_name(mpi_summary_entry_name(entry))
      name = repeat(' ', 2*entry%depth)//escaped_name
   end function display_mpi_name

   function display_mpi_union_name(entry) result(name)
      type(ftimer_mpi_union_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name
      character(len=:), allocatable :: escaped_name

      escaped_name = escaped_summary_name(mpi_union_summary_entry_name(entry))
      name = repeat(' ', 2*entry%depth)//escaped_name
   end function display_mpi_union_name

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

   integer function metadata_key_display_len(item) result(width)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      text = metadata_key_display_text(item)
      width = len(text)
   end function metadata_key_display_len

   function metadata_key_display_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      text = escaped_report_text(metadata_key_text(item), '<blank>')
   end function metadata_key_display_text

   function metadata_value_display_text(item) result(text)
      type(ftimer_metadata_t), intent(in) :: item
      character(len=:), allocatable :: text

      text = escaped_report_text(metadata_value_text(item), '')
   end function metadata_value_display_text

   function escaped_summary_name(name) result(escaped)
      character(len=*), intent(in) :: name
      character(len=:), allocatable :: escaped

      escaped = escaped_report_text(name, '<blank>')
   end function escaped_summary_name

   function escaped_report_text(raw_text, blank_text) result(escaped)
      character(len=*), intent(in) :: raw_text
      character(len=*), intent(in) :: blank_text
      character(len=:), allocatable :: escaped
      integer :: i
      integer :: seq_len
      integer :: visible_len
      logical :: leading_space

      escaped = ''
      visible_len = len_trim(raw_text)
      if (visible_len <= 0) then
         escaped = blank_text
         return
      end if

      leading_space = .true.

      i = 1
      do while (i <= visible_len)
         if (leading_space .and. (raw_text(i:i) == ' ')) then
            escaped = escaped//'\x20'
            i = i + 1
            cycle
         end if

         leading_space = .false.
         seq_len = valid_utf8_sequence_len(raw_text, i, visible_len)
         if (seq_len > 0) then
            if (is_utf8_encoded_c1_control(raw_text, i, seq_len)) then
               call append_escaped_bytes(escaped, raw_text(i:i + seq_len - 1))
            else
               escaped = escaped//raw_text(i:i + seq_len - 1)
            end if
            i = i + seq_len
            cycle
         end if

         call append_escaped_char(escaped, raw_text(i:i))
         i = i + 1
      end do
   end function escaped_report_text

   integer function valid_utf8_sequence_len(text, start, visible_len) result(seq_len)
      character(len=*), intent(in) :: text
      integer, intent(in) :: start
      integer, intent(in) :: visible_len
      integer :: b1
      integer :: b2

      seq_len = 0
      b1 = iachar(text(start:start))

      select case (b1)
      case (194:223)
         if (has_utf8_continuations(text, start, visible_len, 2)) seq_len = 2
      case (224)
         if (start + 2 <= visible_len) then
            b2 = iachar(text(start + 1:start + 1))
            if ((b2 >= 160) .and. (b2 <= 191) .and. &
                is_utf8_continuation_code(iachar(text(start + 2:start + 2)))) seq_len = 3
         end if
      case (225:236, 238:239)
         if (has_utf8_continuations(text, start, visible_len, 3)) seq_len = 3
      case (237)
         if (start + 2 <= visible_len) then
            b2 = iachar(text(start + 1:start + 1))
            if ((b2 >= 128) .and. (b2 <= 159) .and. &
                is_utf8_continuation_code(iachar(text(start + 2:start + 2)))) seq_len = 3
         end if
      case (240)
         if (start + 3 <= visible_len) then
            b2 = iachar(text(start + 1:start + 1))
            if ((b2 >= 144) .and. (b2 <= 191) .and. &
                is_utf8_continuation_code(iachar(text(start + 2:start + 2))) .and. &
                is_utf8_continuation_code(iachar(text(start + 3:start + 3)))) seq_len = 4
         end if
      case (241:243)
         if (has_utf8_continuations(text, start, visible_len, 4)) seq_len = 4
      case (244)
         if (start + 3 <= visible_len) then
            b2 = iachar(text(start + 1:start + 1))
            if ((b2 >= 128) .and. (b2 <= 143) .and. &
                is_utf8_continuation_code(iachar(text(start + 2:start + 2))) .and. &
                is_utf8_continuation_code(iachar(text(start + 3:start + 3)))) seq_len = 4
         end if
      end select
   end function valid_utf8_sequence_len

   logical function has_utf8_continuations(text, start, visible_len, seq_len) result(is_valid)
      character(len=*), intent(in) :: text
      integer, intent(in) :: start
      integer, intent(in) :: visible_len
      integer, intent(in) :: seq_len
      integer :: i

      is_valid = .false.
      if (start + seq_len - 1 > visible_len) return

      do i = start + 1, start + seq_len - 1
         if (.not. is_utf8_continuation_code(iachar(text(i:i)))) return
      end do
      is_valid = .true.
   end function has_utf8_continuations

   logical function is_utf8_continuation_code(code) result(is_continuation)
      integer, intent(in) :: code

      is_continuation = (code >= 128) .and. (code <= 191)
   end function is_utf8_continuation_code

   logical function is_utf8_encoded_c1_control(text, start, seq_len) result(is_control)
      character(len=*), intent(in) :: text
      integer, intent(in) :: start
      integer, intent(in) :: seq_len
      integer :: b1
      integer :: b2

      is_control = .false.
      if (seq_len /= 2) return

      b1 = iachar(text(start:start))
      b2 = iachar(text(start + 1:start + 1))
      is_control = (b1 == 194) .and. (b2 >= 128) .and. (b2 <= 159)
   end function is_utf8_encoded_c1_control

   subroutine append_escaped_bytes(text, bytes)
      character(len=:), allocatable, intent(inout) :: text
      character(len=*), intent(in) :: bytes
      integer :: i

      do i = 1, len(bytes)
         call append_hex_escape(text, iachar(bytes(i:i)))
      end do
   end subroutine append_escaped_bytes

   subroutine append_escaped_char(text, ch)
      character(len=:), allocatable, intent(inout) :: text
      character(len=1), intent(in) :: ch
      integer :: code

      code = iachar(ch)
      select case (code)
      case (9)
         text = text//'\t'
      case (10)
         text = text//'\n'
      case (13)
         text = text//'\r'
      case (92)
         text = text//'\\'
      case (0:8, 11:12, 14:31, 127:159)
         call append_hex_escape(text, code)
      case default
         text = text//ch
      end select
   end subroutine append_escaped_char

   subroutine append_hex_escape(text, code)
      character(len=:), allocatable, intent(inout) :: text
      integer, intent(in) :: code
      character(len=*), parameter :: hex_digits = '0123456789ABCDEF'
      integer :: high_nibble
      integer :: low_nibble

      high_nibble = code/16
      low_nibble = mod(code, 16)
      text = text//'\x'//hex_digits(high_nibble + 1:high_nibble + 1)//hex_digits(low_nibble + 1:low_nibble + 1)
   end subroutine append_hex_escape

end module ftimer_summary
