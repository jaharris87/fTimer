program ftimer_installed_consumer
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_guard_t, ftimer_init, ftimer_scope
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

   scoped_consumer_work: block
      type(ftimer_guard_t) :: guard

      call ftimer_scope(guard, consumer_name, ierr=ierr)
      if (ierr /= 0) error stop 2

      accumulator = 0.0
      do i = 1, 200000
         accumulator = accumulator + real(i)
      end do
   end block scoped_consumer_work

   call ftimer_get_summary(summary, ierr=ierr)
   if (ierr /= 0) error stop 3
   if (summary%num_entries /= 1) error stop 4
   if (trim(summary%entries(1)%name) /= consumer_name) error stop 5
   if (summary%entries(1)%node_id <= 0) error stop 6
   if (summary%entries(1)%parent_id /= 0) error stop 7
   if (summary%entries(1)%call_count /= 1) error stop 8
   if (summary%entries(1)%inclusive_time < 0.0_wp) error stop 9

   call ftimer_finalize(ierr=ierr)
   if (ierr /= 0) error stop 10

   if (accumulator < 0.0) print *, accumulator
end program ftimer_installed_consumer
