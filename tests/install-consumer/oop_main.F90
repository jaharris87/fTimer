program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_guard_t, ftimer_scope, ftimer_t
   use ftimer_types, only: ftimer_summary_t, wp
   implicit none
   type(ftimer_t), target :: timer
   type(ftimer_t), pointer :: timer_ptr
   type(ftimer_summary_t) :: summary
   integer :: ierr

   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1
   timer_ptr => timer

   block
      type(ftimer_guard_t) :: guard

      call ftimer_scope(timer_ptr, guard, "oop-consumer", ierr=ierr)
      if (ierr /= 0) error stop 3
   end block

   call timer%get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 4
   if (summary%num_entries /= 1) error stop 5
   if (trim(summary%entries(1)%name) /= "oop-consumer") error stop 6
   if (summary%entries(1)%call_count /= 1) error stop 7
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 8
   if (summary%has_active_timers) error stop 9

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 2
end program ftimer_installed_oop_consumer
