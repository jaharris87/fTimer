module ftimer_summary
   use ftimer_types, only: FTIMER_MPI_SUMMARY_LOCAL_ONLY, FTIMER_NAME_LEN, ftimer_call_stack_t, ftimer_metadata_t, &
                           ftimer_segment_t, ftimer_summary_entry_t, ftimer_summary_t, wp
   implicit none
   private

   public :: build_summary
   public :: format_summary
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
      summary%has_mpi_data = .false.
      summary%mpi_summary_state = FTIMER_MPI_SUMMARY_LOCAL_ONLY

      if (present(segments)) then
         summary%num_entries = count_visible_summary_nodes(segments, end_time)
      else
         summary%num_entries = 0
      end if

      allocate (summary%entries(summary%num_entries))
      if (summary%num_entries <= 0) return

      call populate_summary_entries(summary%entries, segments, summary%total_time, end_time)
   end subroutine build_summary

   subroutine format_summary(summary, text, metadata)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      character(len=64) :: fmt
      character(len=:), allocatable :: line
      character(len=:), allocatable :: padded
      integer :: i
      integer :: key_width
      integer :: line_width
      integer :: name_width

      text = ''
      key_width = metadata_key_width(metadata)
      name_width = summary_name_width(summary)
      line_width = summary_line_width(name_width)
      allocate (character(len=line_width) :: line)

      write (line, '(f0.6)') summary%total_time
      call set_padded_text(padded, 'Total time (s)', key_width)
      call append_line(text, padded(1:key_width)//' : '//trim(line))

      if (present(metadata)) then
         do i = 1, size(metadata)
            if (len_trim(metadata(i)%key) <= 0) cycle
            call set_padded_text(padded, trim(metadata(i)%key), key_width)
            call append_line(text, padded(1:key_width)//' : '//trim(metadata(i)%value))
         end do
      end if

      call append_line(text, '')
      call set_padded_text(padded, 'Timer name', name_width)
      line = repeat(' ', len(line))
      line(1:name_width + len('  Inclusive (s)     Self (s)    Calls   % Total')) = &
         padded(1:name_width)//'  Inclusive (s)     Self (s)    Calls   % Total'
      call append_line(text, trim(line))
      call append_line(text, repeat('-', len_trim(line)))

      write (fmt, '("(a",i0,",2x,f12.6,2x,f12.6,2x,i8,2x,f8.2)")') name_width
      do i = 1, summary%num_entries
         call set_padded_text(padded, display_name(summary%entries(i)), name_width)
         write (line, fmt) padded(1:name_width), summary%entries(i)%inclusive_time, &
            summary%entries(i)%self_time, summary%entries(i)%call_count, summary%entries(i)%pct_time
         call append_line(text, trim(line))
      end do
   end subroutine format_summary

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
      summary%start_date = ''
      summary%end_date = ''
      summary%total_time = 0.0_wp
      summary%has_mpi_data = .false.
      summary%num_entries = 0
      summary%mpi_summary_state = FTIMER_MPI_SUMMARY_LOCAL_ONLY
   end subroutine clear_summary

   integer function count_visible_summary_nodes(segments, end_time) result(visible_count)
      type(ftimer_segment_t), intent(in) :: segments(:)
      real(wp), intent(in) :: end_time
      integer :: ctx
      integer :: i

      visible_count = 0
      do i = 1, size(segments)
         do ctx = 1, segments(i)%contexts%count
            if (.not. context_is_visible(segments(i), ctx, end_time)) cycle
            visible_count = visible_count + 1
         end do
      end do
   end function count_visible_summary_nodes

   subroutine populate_summary_entries(entries, segments, total_time, end_time)
      type(ftimer_summary_entry_t), intent(inout) :: entries(:)
      type(ftimer_segment_t), intent(in) :: segments(:)
      real(wp), intent(in) :: total_time
      real(wp), intent(in) :: end_time
      integer :: first_child(0:size(entries))
      integer :: last_child(0:size(entries))
      integer :: next_sibling(size(entries))
      integer :: node_call_count(size(entries))
      integer :: node_ctx(size(entries))
      integer :: node_depth(size(entries))
      integer :: node_parent(size(entries))
      integer :: node_segment(size(entries))
      integer :: path_child(0:size(entries), size(segments))
      integer :: ctx
      integer :: depth
      integer :: i
      integer :: max_depth
      integer :: node
      integer :: position
      real(wp) :: node_inclusive(size(entries))

      first_child = 0
      last_child = 0
      next_sibling = 0
      node_parent = 0
      path_child = 0
      max_depth = 0

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
            max_depth = max(max_depth, node_depth(node))
         end do
      end do

      do depth = 0, max_depth
         do node = 1, size(entries)
            if (node_depth(node) /= depth) cycle

            node_parent(node) = summary_tree_parent(path_child, &
                                                    segments(node_segment(node))%contexts%stacks(node_ctx(node)))
            path_child(node_parent(node), node_segment(node)) = node
         end do
      end do

      do node = 1, size(entries)
         if (first_child(node_parent(node)) <= 0) then
            first_child(node_parent(node)) = node
         else
            next_sibling(last_child(node_parent(node))) = node
         end if
         last_child(node_parent(node)) = node
      end do

      position = 0
      call fill_summary_entries(entries, position, 0, first_child, next_sibling, &
                                segments, node_segment, node_depth, node_inclusive, &
                                node_call_count, total_time)
   end subroutine populate_summary_entries

   integer function summary_tree_parent(path_child, stack) result(parent)
      integer, intent(in) :: path_child(0:, :)
      type(ftimer_call_stack_t), intent(in) :: stack
      integer :: level

      parent = 0
      do level = 1, stack%depth
         parent = path_child(parent, stack%ids(level))
      end do
   end function summary_tree_parent

   function display_name(entry) result(name)
      type(ftimer_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name
      character(len=:), allocatable :: escaped_name

      escaped_name = escaped_summary_name(entry%name)
      name = repeat(' ', 2*entry%depth)//escaped_name
   end function display_name

   recursive subroutine fill_summary_entries(entries, position, node, first_child, &
                                             next_sibling, segments, node_segment, &
                                             node_depth, node_inclusive, node_call_count, &
                                             total_time)
      type(ftimer_summary_entry_t), intent(inout) :: entries(:)
      integer, intent(inout) :: position
      integer, intent(in) :: node
      integer, intent(in) :: first_child(0:)
      integer, intent(in) :: next_sibling(:)
      type(ftimer_segment_t), intent(in) :: segments(:)
      integer, intent(in) :: node_segment(:)
      integer, intent(in) :: node_depth(:)
      real(wp), intent(in) :: node_inclusive(:)
      integer, intent(in) :: node_call_count(:)
      real(wp), intent(in) :: total_time
      integer :: child
      real(wp) :: child_sum

      child = first_child(node)
      do while (child > 0)
         position = position + 1
         entries(position)%name = segments(node_segment(child))%name
         entries(position)%depth = node_depth(child)
         entries(position)%inclusive_time = node_inclusive(child)
         child_sum = direct_child_inclusive(first_child, next_sibling, &
                                            node_inclusive, child)
         entries(position)%self_time = clamp_self_time(entries(position)%inclusive_time - child_sum, &
                                                       entries(position)%inclusive_time)
         entries(position)%call_count = node_call_count(child)
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

         call fill_summary_entries(entries, position, child, first_child, &
                                   next_sibling, segments, node_segment, &
                                   node_depth, node_inclusive, node_call_count, &
                                   total_time)
         child = next_sibling(child)
      end do
   end subroutine fill_summary_entries

   real(wp) function direct_child_inclusive(first_child, next_sibling, &
                                            node_inclusive, node) result(total)
      integer, intent(in) :: first_child(0:)
      integer, intent(in) :: next_sibling(:)
      real(wp), intent(in) :: node_inclusive(:)
      integer, intent(in) :: node
      integer :: child

      total = 0.0_wp
      child = first_child(node)
      do while (child > 0)
         total = total + node_inclusive(child)
         child = next_sibling(child)
      end do
   end function direct_child_inclusive

   real(wp) function clamp_self_time(self_time, inclusive_time) result(clamped)
      real(wp), intent(in) :: self_time
      real(wp), intent(in) :: inclusive_time
      real(wp) :: tolerance

      clamped = self_time
      tolerance = 100.0_wp*epsilon(1.0_wp)*max(1.0_wp, abs(inclusive_time))
      if ((clamped < 0.0_wp) .and. (abs(clamped) <= tolerance)) clamped = 0.0_wp
   end function clamp_self_time

   integer function call_count_for_context(segment, ctx) result(count)
      type(ftimer_segment_t), intent(in) :: segment
      integer, intent(in) :: ctx

      count = 0
      if (.not. allocated(segment%call_count)) return
      if (ctx > size(segment%call_count)) return
      count = segment%call_count(ctx)
   end function call_count_for_context

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

   integer function metadata_key_width(metadata) result(width)
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      integer :: i

      width = len('Total time (s)')
      if (.not. present(metadata)) return

      do i = 1, size(metadata)
         width = max(width, len_trim(metadata(i)%key))
      end do
   end function metadata_key_width

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

   integer function summary_line_width(name_width) result(width)
      integer, intent(in) :: name_width

      width = name_width + 48
   end function summary_line_width

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

   function escaped_summary_name(name) result(escaped)
      character(len=*), intent(in) :: name
      character(len=:), allocatable :: escaped
      integer :: i
      integer :: visible_len
      logical :: leading_space

      escaped = ''
      visible_len = len_trim(name)
      if (visible_len <= 0) then
         escaped = '<blank>'
         return
      end if

      leading_space = .true.

      do i = 1, visible_len
         if (leading_space .and. (name(i:i) == ' ')) then
            escaped = escaped//'\x20'
            cycle
         end if

         leading_space = .false.
         call append_escaped_char(escaped, name(i:i))
      end do
   end function escaped_summary_name

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
      case (0:8, 11:12, 14:31, 127)
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
