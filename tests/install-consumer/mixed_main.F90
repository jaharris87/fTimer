program ftimer_installed_mixed_consumer
   use ftimer
   use ftimer_core
   use ftimer_types, only: ftimer_summary_t, wp
   implicit none
   type(ftimer_t), target :: timer_storage
   type(ftimer_t), pointer :: timer
   type(ftimer_summary_t) :: summary
   integer :: ierr

   call ftimer_init(ierr=ierr)
   if (ierr /= 0) error stop 1

   procedural_scope: block
      type(ftimer_guard_t) :: guard

      call ftimer_scope(guard, "mixed_procedural", ierr=ierr)
      if (ierr /= 0) error stop 2
   end block procedural_scope

   call ftimer_get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 3
   if (summary%num_entries /= 1) error stop 4
   if (trim(summary%entries(1)%name) /= "mixed_procedural") error stop 5
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 6

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 7

   timer => timer_storage
   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 8

   oop_scope: block
      type(ftimer_oop_guard_t) :: guard

      call ftimer_oop_scope(timer, guard, "mixed_oop", ierr=ierr)
      if (ierr /= 0) error stop 9
   end block oop_scope

   call timer%get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 10
   if (summary%num_entries /= 1) error stop 11
   if (trim(summary%entries(1)%name) /= "mixed_oop") error stop 12
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 13

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 14
end program ftimer_installed_mixed_consumer
