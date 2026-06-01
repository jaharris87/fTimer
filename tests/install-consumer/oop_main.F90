program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_t
   use ftimer_types, only: ftimer_summary_t, wp
   implicit none
   type(ftimer_t) :: timer
   type(ftimer_summary_t) :: summary
   integer :: ierr

   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1

   call timer%start("oop_work", ierr=ierr)
   if (ierr /= 0) error stop 2

   call timer%stop("oop_work", ierr=ierr)
   if (ierr /= 0) error stop 3

   call timer%get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 4

   if (summary%num_entries /= 1) error stop 5
   if (.not. allocated(summary%entries)) error stop 6
   if (trim(summary%entries(1)%name) /= "oop_work") error stop 7
   if (summary%entries(1)%call_count /= 1) error stop 8
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 9
   if (summary%entries(1)%self_time < 0.0_wp) error stop 10
   if (summary%total_contexts /= 1) error stop 11
   if (summary%max_contexts_per_timer /= 1) error stop 12
   if (summary%entries(1)%timer_context_count /= 1) error stop 13
   if (summary%num_context_diagnostics /= 1) error stop 14
   if (.not. allocated(summary%context_diagnostics)) error stop 15
   if (trim(summary%context_diagnostics(1)%name) /= "oop_work") error stop 16
   if (summary%context_diagnostics(1)%context_count /= 1) error stop 17

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 18
end program ftimer_installed_oop_consumer
