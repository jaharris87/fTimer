module test_support
   use ftimer_core, only: ftimer_t, ftimer_test_get_state, ftimer_test_state_t
   use ftimer_types, only: ftimer_call_stack_t, wp
   use, intrinsic :: iso_c_binding, only: c_char, c_int, c_null_char, c_null_ptr, c_ptr
   use, intrinsic :: iso_fortran_env, only: error_unit, iostat_end, iostat_eor
   implicit none
   private

   public :: attach_mock_clock
   public :: attach_scripted_mock_clock
   public :: begin_stderr_capture
   public :: build_stack
   public :: end_stderr_capture
   public :: fake_time
   public :: get_mock_clock_call_count
   public :: find_context_idx
   public :: mock_clock
   public :: read_file_text
   public :: reset_mock_clock_state
   public :: read_unit_text
   public :: snapshot_timer

   real(wp), save :: fake_time = 0.0_wp
   real(wp), allocatable, save :: scripted_times(:)
   integer, save :: mock_clock_call_count = 0
   integer, save :: scripted_time_idx = 0
   logical, save :: use_scripted_times = .false.

#ifdef __APPLE__
   integer(c_int), parameter :: O_WRONLY = int(z'0001', c_int)
   integer(c_int), parameter :: O_CREAT = int(z'0200', c_int)
   integer(c_int), parameter :: O_TRUNC = int(z'0400', c_int)
#else
   integer(c_int), parameter :: O_WRONLY = int(z'0001', c_int)
   integer(c_int), parameter :: O_CREAT = int(z'0040', c_int)
   integer(c_int), parameter :: O_TRUNC = int(z'0200', c_int)
#endif
   integer(c_int), parameter :: STDERR_FILENO = 2_c_int
   integer(c_int), parameter :: STDERR_MODE = int(z'0180', c_int)

   interface
      integer(c_int) function c_close(fd) bind(C, name="close")
         import :: c_int
         integer(c_int), value :: fd
      end function c_close

      integer(c_int) function c_dup(fd) bind(C, name="dup")
         import :: c_int
         integer(c_int), value :: fd
      end function c_dup

      integer(c_int) function c_dup2(oldfd, newfd) bind(C, name="dup2")
         import :: c_int
         integer(c_int), value :: oldfd
         integer(c_int), value :: newfd
      end function c_dup2

      integer(c_int) function c_fflush(stream) bind(C, name="fflush")
         import :: c_int, c_ptr
         type(c_ptr), value :: stream
      end function c_fflush

      integer(c_int) function c_open(path, flags, mode) bind(C, name="open")
         import :: c_char, c_int
         character(kind=c_char), intent(in) :: path(*)
         integer(c_int), value :: flags
         integer(c_int), value :: mode
      end function c_open
   end interface

contains

   subroutine attach_mock_clock(timer)
      class(ftimer_t), intent(inout) :: timer

      timer%clock => mock_clock
      call reset_mock_clock_state()
   end subroutine attach_mock_clock

   subroutine attach_scripted_mock_clock(timer, values)
      class(ftimer_t), intent(inout) :: timer
      real(wp), intent(in) :: values(:)

      timer%clock => mock_clock
      call reset_mock_clock_state()
      use_scripted_times = .true.
      allocate (scripted_times(size(values)))
      scripted_times = values
   end subroutine attach_scripted_mock_clock

   subroutine begin_stderr_capture(path, saved_fd, ierr)
      character(len=*), intent(in) :: path
      integer, intent(out) :: saved_fd
      integer, intent(out) :: ierr
      character(kind=c_char, len=:), allocatable :: c_path
      integer(c_int) :: capture_fd
      integer(c_int) :: saved_fd_c

      call delete_file_if_exists(path)

      c_path = trim(path)//c_null_char
      saved_fd_c = c_dup(STDERR_FILENO)
      if (saved_fd_c < 0_c_int) then
         ierr = 1
         saved_fd = -1
         return
      end if

      capture_fd = c_open(c_path, O_WRONLY + O_CREAT + O_TRUNC, STDERR_MODE)
      if (capture_fd < 0_c_int) then
         ierr = 1
         saved_fd = int(saved_fd_c)
         if (c_close(saved_fd_c) < 0_c_int) ierr = 1
         saved_fd = -1
         return
      end if

      if (c_dup2(capture_fd, STDERR_FILENO) < 0_c_int) then
         ierr = 1
         saved_fd = int(saved_fd_c)
         if (c_close(capture_fd) < 0_c_int) ierr = 1
         if (c_close(saved_fd_c) < 0_c_int) ierr = 1
         saved_fd = -1
         return
      end if

      if (c_close(capture_fd) < 0_c_int) then
         ierr = 1
         if (c_dup2(saved_fd_c, STDERR_FILENO) < 0_c_int) ierr = 1
         if (c_close(saved_fd_c) < 0_c_int) ierr = 1
         saved_fd = -1
         return
      end if
      saved_fd = int(saved_fd_c)
      ierr = 0
   end subroutine begin_stderr_capture

   subroutine end_stderr_capture(path, saved_fd, text, ierr)
      character(len=*), intent(in) :: path
      integer, intent(inout) :: saved_fd
      character(len=:), allocatable, intent(out) :: text
      integer, intent(out) :: ierr
      integer(c_int) :: saved_fd_c

      ierr = 0
      flush (error_unit)
      if (c_fflush(c_null_ptr) < 0_c_int) ierr = 1

      if (saved_fd < 0) then
         text = ''
         ierr = 1
         return
      end if

      saved_fd_c = int(saved_fd, c_int)
      if (c_dup2(saved_fd_c, STDERR_FILENO) < 0_c_int) ierr = 1
      if (c_close(saved_fd_c) < 0_c_int) ierr = 1
      saved_fd = -1

      text = read_file_text(path)
      call delete_file_if_exists(path)
   end subroutine end_stderr_capture

   type(ftimer_call_stack_t) function build_stack(ids) result(stack)
      integer, intent(in) :: ids(:)
      integer :: i

      do i = 1, size(ids)
         call stack%push(ids(i))
      end do
   end function build_stack

   integer function find_context_idx(state, segment_id, stack) result(ctx)
      type(ftimer_test_state_t), intent(in) :: state
      integer, intent(in) :: segment_id
      type(ftimer_call_stack_t), intent(in) :: stack

      ctx = state%segments(segment_id)%contexts%find(stack)
   end function find_context_idx

   function mock_clock() result(t)
      real(wp) :: t

      mock_clock_call_count = mock_clock_call_count + 1

      if (use_scripted_times) then
         if (.not. allocated(scripted_times)) error stop "scripted mock clock is not configured"
         if (scripted_time_idx >= size(scripted_times)) error stop "scripted mock clock exhausted"

         scripted_time_idx = scripted_time_idx + 1
         t = scripted_times(scripted_time_idx)
         return
      end if

      t = fake_time
   end function mock_clock

   integer function get_mock_clock_call_count() result(count)
      count = mock_clock_call_count
   end function get_mock_clock_call_count

   subroutine reset_mock_clock_state()
      fake_time = 0.0_wp
      mock_clock_call_count = 0
      scripted_time_idx = 0
      use_scripted_times = .false.
      if (allocated(scripted_times)) deallocate (scripted_times)
   end subroutine reset_mock_clock_state

   subroutine snapshot_timer(timer, state)
      class(ftimer_t), intent(in) :: timer
      type(ftimer_test_state_t), intent(out) :: state

      call ftimer_test_get_state(timer, state)
   end subroutine snapshot_timer

   function read_file_text(path) result(text)
      character(len=*), intent(in) :: path
      character(len=:), allocatable :: text
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='old', action='read', iostat=io)
      if (io /= 0) then
         text = ''
         return
      end if

      text = read_unit_text(unit)
      close (unit)
   end function read_file_text

   function read_unit_text(unit) result(text)
      integer, intent(in) :: unit
      character(len=:), allocatable :: text
      character(len=256) :: chunk
      character(len=:), allocatable :: line
      integer :: chars_read
      integer :: io
      logical :: first_line

      rewind (unit)
      text = ''
      first_line = .true.

      read_lines: do
         line = ''

         read_chunks: do
            chunk = ''
            read (unit, '(a)', advance='no', iostat=io, size=chars_read) chunk

            if (chars_read > 0) then
               line = line//chunk(1:chars_read)
            end if

            if (io == 0) cycle read_chunks
            if ((io == iostat_eor) .or. ((io == iostat_end) .and. (len(line) > 0))) exit read_chunks
            if (io == iostat_end) exit read_lines
            exit read_lines
         end do read_chunks

         if (.not. first_line) text = text//new_line('a')
         text = text//line
         first_line = .false.
      end do read_lines

      if (.not. first_line) text = text//new_line('a')
   end function read_unit_text

   subroutine delete_file_if_exists(path)
      character(len=*), intent(in) :: path
      integer :: io
      integer :: unit

      open (newunit=unit, file=path, status='old', iostat=io)
      if (io == 0) close (unit, status='delete')
   end subroutine delete_file_if_exists

end module test_support
