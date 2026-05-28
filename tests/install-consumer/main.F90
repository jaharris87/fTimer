program ftimer_installed_consumer
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, ftimer_scope, ftimer_scope_guard_t, &
                     ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t, wp
   implicit none
   character(len=*), parameter :: consumer_name = &
                                  "consumer_work_with_scientific_module_path_longer_than_the_legacy_sixty_four_character_threshold"
   integer :: ierr
   integer :: i
   real :: accumulator
   type(ftimer_summary_t) :: summary

   call ftimer_init(ierr=ierr)
   if (ierr /= 0) error stop 1

   call ftimer_start(consumer_name, ierr=ierr)
   if (ierr /= 0) error stop 2

   accumulator = 0.0
   do i = 1, 200000
      accumulator = accumulator + real(i)
   end do

   call ftimer_stop(consumer_name, ierr=ierr)
   if (ierr /= 0) error stop 3

   block
      type(ftimer_scope_guard_t) :: guard

      call ftimer_scope(guard, "consumer_scoped_work", ierr=ierr)
      if (ierr /= 0) error stop 4
      accumulator = accumulator + 1.0
   end block

   call ftimer_get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 5
   if (summary%num_entries /= 2) error stop 6
   if (trim(summary%entries(1)%name) /= consumer_name) error stop 7
   if (summary%entries(1)%node_id <= 0) error stop 8
   if (summary%entries(1)%parent_id /= 0) error stop 9
   if (summary%entries(1)%call_count /= 1) error stop 10
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 11
   if (trim(summary%entries(2)%name) /= "consumer_scoped_work") error stop 12
   if (summary%entries(2)%call_count /= 1) error stop 13

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 14

   if (accumulator < 0.0) print *, accumulator
end program ftimer_installed_consumer
