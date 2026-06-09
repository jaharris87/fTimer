module ftimer_csv_validation
   use, intrinsic :: iso_fortran_env, only: iostat_end
   use ftimer_types, only: FTIMER_ERR_IO, FTIMER_SUCCESS
   implicit none
   private

   public :: ftimer_get_csv_append_header_mode

contains

   subroutine ftimer_get_csv_append_header_mode(filename, append_mode, include_header, status, iomsg, &
                                                expected_header, format_version, summary_kinds, record_types, &
                                                header_mismatch_message, record_mismatch_message, &
                                                bare_cr_message, malformed_quote_message, no_newline_message, &
                                                unterminated_quote_message)
      character(len=*), intent(in) :: filename
      logical, intent(in) :: append_mode
      logical, intent(out) :: include_header
      integer, intent(out) :: status
      character(len=*), intent(out) :: iomsg
      character(len=*), intent(in) :: expected_header
      character(len=*), intent(in) :: format_version
      character(len=*), intent(in) :: summary_kinds(:)
      character(len=*), intent(in) :: record_types(:)
      character(len=*), intent(in) :: header_mismatch_message
      character(len=*), intent(in) :: record_mismatch_message
      character(len=*), intent(in) :: bare_cr_message
      character(len=*), intent(in) :: malformed_quote_message
      character(len=*), intent(in) :: no_newline_message
      character(len=*), intent(in) :: unterminated_quote_message
      character(len=1) :: ch
      character(len=:), allocatable :: header_line
      character(len=:), allocatable :: record_text
      character(len=1) :: last_char
      integer :: expected_field_count
      integer :: file_unit
      integer :: io
      integer :: record_field_count
      integer :: record_prefix_limit
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
                  iomsg = header_mismatch_message
                  return
               end if
            else
               if (len(header_line) >= len(expected_header) + 1) then
                  close (file_unit)
                  status = FTIMER_ERR_IO
                  iomsg = header_mismatch_message
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
               iomsg = bare_cr_message
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
               iomsg = malformed_quote_message
               return
            end if
         end if

         if ((ch == new_line('a')) .and. (.not. in_quotes)) then
            call strip_trailing_carriage_return(record_text)
            if ((record_field_count /= expected_field_count) .or. &
                (.not. csv_record_has_allowed_prefix(record_text, format_version, summary_kinds, record_types))) then
               close (file_unit)
               status = FTIMER_ERR_IO
               iomsg = record_mismatch_message
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
               iomsg = malformed_quote_message
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
         iomsg = no_newline_message
         return
      end if

      if (in_quotes) then
         status = FTIMER_ERR_IO
         iomsg = unterminated_quote_message
         return
      end if

      if (pending_record_cr) then
         status = FTIMER_ERR_IO
         iomsg = bare_cr_message
         return
      end if

      include_header = .false.
   end subroutine ftimer_get_csv_append_header_mode

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

   logical function csv_record_has_allowed_prefix(line, format_version, summary_kinds, record_types) result(matches)
      character(len=*), intent(in) :: line
      character(len=*), intent(in) :: format_version
      character(len=*), intent(in) :: summary_kinds(:)
      character(len=*), intent(in) :: record_types(:)
      integer :: kind_idx
      integer :: type_idx

      matches = .false.
      do kind_idx = 1, size(summary_kinds)
         do type_idx = 1, size(record_types)
            if (starts_with(line, '"'//trim(format_version)//'","'//trim(summary_kinds(kind_idx))// &
                            '","'//trim(record_types(type_idx))//'",')) then
               matches = .true.
               return
            end if
         end do
      end do
   end function csv_record_has_allowed_prefix

   logical function starts_with(text, prefix) result(matches)
      character(len=*), intent(in) :: text
      character(len=*), intent(in) :: prefix

      matches = .false.
      if (len_trim(text) < len(prefix)) return
      matches = text(1:len(prefix)) == prefix
   end function starts_with

end module ftimer_csv_validation
