program openmp_worker_example
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_parallel_region_t, &
                            ftimer_openmp_summary_t, ftimer_openmp_t
   use ftimer_types, only: FTIMER_SUCCESS, wp
   use omp_lib, only: omp_get_thread_num, omp_set_dynamic
   implicit none

   integer :: entry_idx
   integer :: ierr
   integer :: i
   integer :: team_work_id
   integer :: worker_bad
   integer :: worker_seen
   real(wp) :: accumulator
   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_parallel_region_t) :: region
   type(ftimer_openmp_summary_t) :: summary
   type(ftimer_openmp_t) :: timer

   call omp_set_dynamic(.false.)

   config%max_lanes = 3
   config%max_worker_diagnostics = 4

   ! ftimer_openmp_t is the opt-in path for true worker timings; configure lane
   ! capacity before init so each OpenMP thread has storage to write into.
   call timer%init(config=config, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp init failed"

   ! Register once outside the parallel region and use ids inside hot loops to
   ! avoid repeated name lookups.
   call timer%register_timer("team_work", team_work_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp register_timer failed"

   ! The region handle brackets one OpenMP team and must be opened and closed by
   ! serial code around the !$omp parallel block.
   call timer%begin_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp begin_parallel_region failed"

   accumulator = 0.0_wp
   worker_bad = 0
   worker_seen = 0

!$omp parallel num_threads(2) default(shared) private(ierr, i) &
!$omp& reduction(+:accumulator, worker_bad, worker_seen)
   worker_seen = worker_seen + 1

   ! Each worker lane records its own local interval for the same registered id.
   call timer%start_id(team_work_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1

   do i = 1, (omp_get_thread_num() + 1)*60000
      accumulator = accumulator + real(i, wp)*0.5_wp
   end do

   call timer%stop_id(team_work_id, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) worker_bad = worker_bad + 1
!$omp end parallel

   if (worker_seen /= 2) error stop "OpenMP worker example expected two threads"
   if (worker_bad /= 0) error stop "OpenMP worker timing failed"

   call timer%end_parallel_region(region, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp end_parallel_region failed"

   call timer%get_openmp_summary(summary, ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp get_openmp_summary failed"

   entry_idx = find_entry(summary, "team_work")
   if (entry_idx <= 0) error stop "OpenMP worker example did not record team_work"
   if (summary%entries(entry_idx)%participating_lane_count /= 2) &
      error stop "OpenMP worker example expected two participating lanes"
   if (summary%entries(entry_idx)%min_lane_call_count /= 1) &
      error stop "OpenMP worker example expected one call per lane"
   if (summary%entries(entry_idx)%max_lane_call_count /= 1) &
      error stop "OpenMP worker example expected one call per lane"

   print '(a)', "True OpenMP worker timing with ftimer_openmp_t"
   print '(a,i0)', "Recorded OpenMP entries: ", summary%num_entries
   print '(a,i0)', "Participating lanes for team_work: ", &
      summary%entries(entry_idx)%participating_lane_count
   call timer%print_openmp_summary(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp print_openmp_summary failed"
   call timer%write_openmp_summary_csv("openmp_worker_summary.csv", ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp write_openmp_summary_csv failed"

   call timer%finalize(ierr=ierr)
   if (ierr /= FTIMER_SUCCESS) error stop "ftimer_openmp finalize failed"

   if (accumulator < 0.0_wp) print *, accumulator

contains

   integer function find_entry(summary, name) result(entry_idx)
      type(ftimer_openmp_summary_t), intent(in) :: summary
      character(len=*), intent(in) :: name
      integer :: i

      entry_idx = 0
      do i = 1, summary%num_entries
         if (trim(summary%entries(i)%name) == name) then
            entry_idx = i
            return
         end if
      end do
   end function find_entry

end program openmp_worker_example
