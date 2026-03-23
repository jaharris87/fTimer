module ftimer_summary
   use ftimer_types, only: FTIMER_NAME_LEN, ftimer_call_stack_t, ftimer_metadata_t, ftimer_segment_t, &
                           ftimer_summary_entry_t, ftimer_summary_t, wp
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
      type(ftimer_call_stack_t) :: root_stack
      integer :: position

      call clear_summary(summary)
      summary%start_date = init_date
      summary%end_date = end_date
      summary%total_time = max(0.0_wp, end_time - init_wtime)
      summary%has_mpi_data = .false.
      summary%placeholder = 0

      if (present(segments)) then
         summary%num_entries = count_summary_entries(segments, root_stack, end_time)
      else
         summary%num_entries = 0
      end if

      allocate (summary%entries(summary%num_entries))
      if (summary%num_entries <= 0) return

      position = 0
      call fill_summary_entries(summary%entries, position, segments, root_stack, 0, summary%total_time, end_time)
      call compute_self_times(summary)
   end subroutine build_summary

   subroutine format_summary(summary, text, metadata)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: text
      type(ftimer_metadata_t), intent(in), optional :: metadata(:)
      character(len=256) :: fmt
      character(len=256) :: line
      character(len=256) :: padded
      integer :: i
      integer :: key_width
      integer :: name_width

      text = ''
      key_width = metadata_key_width(metadata)
      name_width = summary_name_width(summary)

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
      line = padded(1:name_width)//'  Inclusive (s)     Self (s)    Calls   % Total'
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
      summary%placeholder = 0
   end subroutine clear_summary

   subroutine compute_self_times(summary)
      type(ftimer_summary_t), intent(inout) :: summary
      integer :: i
      integer :: j
      real(wp) :: child_sum
      real(wp) :: tolerance

      do i = 1, summary%num_entries
         child_sum = 0.0_wp
         j = i + 1
         do while (j <= summary%num_entries)
            if (summary%entries(j)%depth <= summary%entries(i)%depth) exit
            if (summary%entries(j)%depth == summary%entries(i)%depth + 1) then
               child_sum = child_sum + summary%entries(j)%inclusive_time
            end if
            j = j + 1
         end do

         summary%entries(i)%self_time = summary%entries(i)%inclusive_time - child_sum
         tolerance = 100.0_wp*epsilon(1.0_wp)*max(1.0_wp, abs(summary%entries(i)%inclusive_time))
         if ((summary%entries(i)%self_time < 0.0_wp) .and. (abs(summary%entries(i)%self_time) <= tolerance)) then
            summary%entries(i)%self_time = 0.0_wp
         end if
      end do
   end subroutine compute_self_times

   recursive integer function count_summary_entries(segments, parent_stack, end_time) result(count)
      type(ftimer_segment_t), intent(in) :: segments(:)
      type(ftimer_call_stack_t), intent(in) :: parent_stack
      real(wp), intent(in) :: end_time
      type(ftimer_call_stack_t) :: child_stack
      integer :: ctx
      integer :: i

      count = 0
      do i = 1, size(segments)
         ctx = segments(i)%contexts%find(parent_stack)
         if (ctx <= 0) cycle
         if (.not. context_is_visible(segments(i), ctx, end_time)) cycle

         count = count + 1
         call child_stack%copy(parent_stack)
         call child_stack%push(i)
         count = count + count_summary_entries(segments, child_stack, end_time)
      end do
   end function count_summary_entries

   function display_name(entry) result(name)
      type(ftimer_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name
      integer :: name_len

      name_len = max(1, len_trim(entry%name) + 2*entry%depth)
      allocate (character(len=name_len) :: name)
      name = repeat(' ', 2*entry%depth)//trim(entry%name)
   end function display_name

   recursive subroutine fill_summary_entries(entries, position, segments, parent_stack, depth, total_time, end_time)
      type(ftimer_summary_entry_t), intent(inout) :: entries(:)
      integer, intent(inout) :: position
      type(ftimer_segment_t), intent(in) :: segments(:)
      type(ftimer_call_stack_t), intent(in) :: parent_stack
      integer, intent(in) :: depth
      real(wp), intent(in) :: total_time
      real(wp), intent(in) :: end_time
      type(ftimer_call_stack_t) :: child_stack
      integer :: ctx
      integer :: i

      do i = 1, size(segments)
         ctx = segments(i)%contexts%find(parent_stack)
         if (ctx <= 0) cycle
         if (.not. context_is_visible(segments(i), ctx, end_time)) cycle

         position = position + 1
         entries(position)%name = segments(i)%name
         entries(position)%depth = depth
         entries(position)%inclusive_time = inclusive_for_context(segments(i), ctx, end_time)
         entries(position)%self_time = entries(position)%inclusive_time
         entries(position)%call_count = call_count_for_context(segments(i), ctx)
         if (entries(position)%call_count > 0) then
            entries(position)%avg_time = entries(position)%inclusive_time/real(entries(position)%call_count, wp)
         else
            entries(position)%avg_time = 0.0_wp
         end if
         if (total_time > 0.0_wp) then
            entries(position)%pct_time = 100.0_wp*entries(position)%inclusive_time/total_time
         else
            entries(position)%pct_time = 0.0_wp
         end if

         call child_stack%copy(parent_stack)
         call child_stack%push(i)
         call fill_summary_entries(entries, position, segments, child_stack, depth + 1, total_time, end_time)
      end do
   end subroutine fill_summary_entries

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
            if (segment%is_running(ctx)) total = total + max(0.0_wp, end_time - segment%start_time(ctx))
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
            if (segment%is_running(ctx)) is_visible = end_time >= segment%start_time(ctx)
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
      character(len=*), intent(out) :: padded
      character(len=*), intent(in) :: text
      integer, intent(in) :: width
      integer :: copy_len

      padded = ''
      copy_len = min(width, len_trim(text), len(padded))
      if (copy_len > 0) padded(1:copy_len) = text(1:copy_len)
   end subroutine set_padded_text

   integer function summary_name_width(summary) result(width)
      type(ftimer_summary_t), intent(in) :: summary
      integer :: i

      width = len('Timer name')
      do i = 1, summary%num_entries
         width = max(width, len_trim(summary%entries(i)%name) + 2*summary%entries(i)%depth)
      end do
   end function summary_name_width

end module ftimer_summary
