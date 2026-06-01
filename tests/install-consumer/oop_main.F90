program ftimer_installed_oop_consumer
   use ftimer_core, only: ftimer_oop_guard_t, ftimer_scope, ftimer_t
   use ftimer_types, only: ftimer_summary_t, wp
   implicit none
   type(ftimer_t), target :: timer_storage
   type(ftimer_t), pointer :: timer
   type(ftimer_summary_t) :: summary
   integer :: i
   integer :: ierr
   logical :: saw_explicit
   logical :: saw_scoped

   timer => timer_storage
   call timer%init(ierr=ierr)
   if (ierr /= 0) error stop 1

   call timer%start("oop_work", ierr=ierr)
   if (ierr /= 0) error stop 2

   call timer%stop("oop_work", ierr=ierr)
   if (ierr /= 0) error stop 3

   scoped_oop_work: block
      type(ftimer_oop_guard_t) :: guard

      call ftimer_scope(timer, guard, "oop_scoped_work", ierr=ierr)
      if (ierr /= 0) error stop 4
   end block scoped_oop_work

   call timer%get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 5

   if (summary%num_entries /= 2) error stop 6
   if (.not. allocated(summary%entries)) error stop 7
   if (summary%total_contexts /= 2) error stop 8
   if (summary%max_contexts_per_timer /= 1) error stop 9
   if (summary%num_context_diagnostics /= 2) error stop 10
   if (.not. allocated(summary%context_diagnostics)) error stop 11

   saw_explicit = .false.
   saw_scoped = .false.
   do i = 1, summary%num_entries
      select case (trim(summary%entries(i)%name))
      case ("oop_work")
         saw_explicit = .true.
      case ("oop_scoped_work")
         saw_scoped = .true.
      case default
         error stop 12
      end select
      if (summary%entries(i)%call_count /= 1) error stop 13
      if (summary%entries(i)%inclusive_time < 0.0_wp) error stop 14
      if (summary%entries(i)%self_time < 0.0_wp) error stop 15
      if (summary%entries(i)%timer_context_count /= 1) error stop 16
   end do

   if (.not. saw_explicit) error stop 17
   if (.not. saw_scoped) error stop 18

   saw_explicit = .false.
   saw_scoped = .false.
   do i = 1, summary%num_context_diagnostics
      select case (trim(summary%context_diagnostics(i)%name))
      case ("oop_work")
         saw_explicit = .true.
      case ("oop_scoped_work")
         saw_scoped = .true.
      case default
         error stop 19
      end select
      if (summary%context_diagnostics(i)%context_count /= 1) error stop 20
   end do

   if (.not. saw_explicit) error stop 21
   if (.not. saw_scoped) error stop 22

   call timer%finalize(ierr=ierr)
   if (ierr /= 0) error stop 23
end program ftimer_installed_oop_consumer
