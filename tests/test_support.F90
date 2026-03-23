module test_support
   use ftimer_core, only: ftimer_t, ftimer_test_get_state, ftimer_test_set_init_wtime, ftimer_test_state_t
   use ftimer_types, only: ftimer_call_stack_t, wp
   implicit none
   private

   public :: attach_mock_clock
   public :: build_stack
   public :: fake_time
   public :: find_context_idx
   public :: mock_clock
   public :: read_file_text
   public :: read_unit_text
   public :: snapshot_timer

   real(wp), save :: fake_time = 0.0_wp

contains

   subroutine attach_mock_clock(timer)
      class(ftimer_t), intent(inout) :: timer

      timer%clock => mock_clock
      fake_time = 0.0_wp
      call ftimer_test_set_init_wtime(timer, fake_time)
   end subroutine attach_mock_clock

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

      t = fake_time
   end function mock_clock

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
      character(len=256) :: line
      integer :: io
      logical :: first_line

      rewind (unit)
      text = ''
      first_line = .true.

      do
         read (unit, '(a)', iostat=io) line
         if (io /= 0) exit

         if (.not. first_line) text = text//new_line('a')
         text = text//trim(line)
         first_line = .false.
      end do

      if (.not. first_line) text = text//new_line('a')
   end function read_unit_text

end module test_support
