module test_support
   use ftimer_core, only: ftimer_t, ftimer_test_get_state, ftimer_test_state_t
   use ftimer_types, only: ftimer_call_stack_t, wp
   implicit none
   private

   public :: attach_mock_clock
   public :: build_stack
   public :: fake_time
   public :: find_context_idx
   public :: mock_clock
   public :: snapshot_timer

   real(wp), save :: fake_time = 0.0_wp

contains

   subroutine attach_mock_clock(timer)
      class(ftimer_t), intent(inout) :: timer

      timer%clock => mock_clock
      fake_time = 0.0_wp
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

end module test_support
