module ftimer_mpi
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, &
                           FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, ftimer_mpi_summary_t, ftimer_summary_entry_t, &
                           ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi
#endif
   implicit none
   private

   public :: build_mpi_summary
   public :: check_mpi_summary_prereqs
   public :: ftimer_mpi_enabled
   public :: get_mpi_summary_comm_info
#ifdef FTIMER_BUILD_TESTS
#ifdef FTIMER_USE_MPI
   public :: ftimer_test_get_mpi_preflight_collectives
   public :: ftimer_test_get_mpi_preflight_mismatch_flags
   public :: ftimer_test_reset_mpi_preflight_collectives
#endif
#endif

#ifdef FTIMER_BUILD_TESTS
#ifdef FTIMER_USE_MPI
   integer :: test_preflight_allgather_count = 0
   integer :: test_preflight_mismatch_flag_allgather_count = 0
   integer :: test_preflight_summary_reduction_count = 0
   integer, allocatable :: test_preflight_mismatch_flags(:)
   logical :: test_preflight_after_descriptor_check = .false.
#endif
#endif

#ifdef FTIMER_USE_MPI
   interface ftimer_mpi_allreduce
      module procedure ftimer_mpi_allreduce_integer_scalar
      module procedure ftimer_mpi_allreduce_integer_array
      module procedure ftimer_mpi_allreduce_int64_array
      module procedure ftimer_mpi_allreduce_real_scalar
      module procedure ftimer_mpi_allreduce_real_array
   end interface
#endif

contains

   subroutine resolve_mpi_summary_comm(comm, active_comm, status)
      integer, intent(in) :: comm
      integer, intent(out) :: active_comm
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      ! Contract: mpi_summary() is collective over the communicator captured at init.
      ! If init omitted `comm`, ftimer_core passes a sentinel and mpi_summary()
      ! resolves that contract to MPI_COMM_WORLD here.
      active_comm = comm
      if (active_comm < 0) active_comm = MPI_COMM_WORLD

      if (active_comm == MPI_COMM_NULL) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      status = FTIMER_SUCCESS
#else
      active_comm = -1
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine resolve_mpi_summary_comm

   logical function ftimer_mpi_enabled()
#ifdef FTIMER_USE_MPI
      ftimer_mpi_enabled = .true.
#else
      ftimer_mpi_enabled = .false.
#endif
   end function ftimer_mpi_enabled

   subroutine get_mpi_summary_comm_info(comm, active_comm, rank, nprocs, status)
      integer, intent(in) :: comm
      integer, intent(out) :: active_comm
      integer, intent(out) :: rank
      integer, intent(out) :: nprocs
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      integer :: mpierr

      call resolve_mpi_summary_comm(comm, active_comm, status)
      if (status /= FTIMER_SUCCESS) then
         rank = -1
         nprocs = 0
         return
      end if

      call MPI_Comm_rank(active_comm, rank, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         rank = -1
         nprocs = 0
         return
      end if

      call MPI_Comm_size(active_comm, nprocs, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         rank = -1
         nprocs = 0
         return
      end if
#else
      active_comm = -1
      rank = -1
      nprocs = 0
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine get_mpi_summary_comm_info

   subroutine check_mpi_summary_prereqs(local_has_active_timers, comm, status)
      logical, intent(in) :: local_has_active_timers
      integer, intent(in) :: comm
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      integer :: active_comm
      integer :: any_active
      integer :: local_active
      integer :: mpierr
      integer :: nprocs
      integer :: rank

      call get_mpi_summary_comm_info(comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) return

      local_active = 0
      if (local_has_active_timers) local_active = 1

      call ftimer_mpi_allreduce(local_active, any_active, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      if (any_active /= 0) status = FTIMER_ERR_ACTIVE
#else
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine check_mpi_summary_prereqs

   subroutine build_mpi_summary(local_summary, comm, summary, status, diagnostic)
      type(ftimer_summary_t), intent(in) :: local_summary
      integer, intent(in) :: comm
      type(ftimer_mpi_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out), optional :: diagnostic
#ifdef FTIMER_USE_MPI
      integer :: active_comm
      integer :: all_datatypes_ready
      integer :: datatypes_ready
      integer :: entry_count
      integer :: i
      integer :: local_idx
      integer :: local_max_total_rank
      integer :: local_min_total_rank
      integer :: max_node_id
      integer :: max_total_time_rank
      integer :: min_total_time_rank
      integer :: mpi_int64_type
      integer :: mpierr
      integer :: mpi_wp_type
      integer :: nprocs
      integer :: parent_entry
      integer :: parent_id
      integer :: rank
      integer, allocatable :: local_calls(:)
      integer, allocatable :: local_entry_to_canonical(:)
      integer, allocatable :: local_max_inclusive_ranks(:)
      integer, allocatable :: local_min_inclusive_ranks(:)
      integer, allocatable :: local_node_to_entry(:)
      integer, allocatable :: max_inclusive_ranks(:)
      integer, allocatable :: max_calls(:)
      integer, allocatable :: min_inclusive_ranks(:)
      integer, allocatable :: min_calls(:)
      integer, allocatable :: mismatch_flags(:)
      integer, allocatable :: permutation(:)
      integer(int64), allocatable :: local_sum_calls(:)
      integer(int64), allocatable :: sum_calls(:)
      integer(int64) :: local_hashes(2)
      integer(int64) :: reference_hashes(2)
      integer :: any_hash_mismatch
      integer :: local_hash_mismatch
      real(wp) :: avg_total_time
      real(wp) :: max_total_time
      real(wp) :: min_total_time
      real(wp) :: sum_total_time
      real(wp), allocatable :: local_inclusive(:)
      real(wp), allocatable :: local_pct(:)
      real(wp), allocatable :: local_self(:)
      real(wp), allocatable :: max_inclusive(:)
      real(wp), allocatable :: max_pct(:)
      real(wp), allocatable :: max_self(:)
      real(wp), allocatable :: min_inclusive(:)
      real(wp), allocatable :: min_pct(:)
      real(wp), allocatable :: min_self(:)
      real(wp), allocatable :: sum_inclusive(:)
      real(wp), allocatable :: sum_pct(:)
      real(wp), allocatable :: sum_self(:)
      character(len=:), allocatable :: descriptors(:)
      logical :: hashes_match

      call clear_mpi_summary(summary)
      if (present(diagnostic)) diagnostic = ''
#ifdef FTIMER_BUILD_TESTS
      test_preflight_after_descriptor_check = .false.
#endif

      call get_mpi_summary_comm_info(comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) return

      call resolve_mpi_summary_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
      datatypes_ready = 0
      if (status == FTIMER_SUCCESS) datatypes_ready = 1
      call ftimer_mpi_allreduce(datatypes_ready, all_datatypes_ready, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if
      if (all_datatypes_ready /= 1) then
         if (status == FTIMER_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            if (present(diagnostic)) diagnostic = &
               "ftimer mpi_summary datatype validation failed on another rank"
         end if
         return
      end if

      call build_descriptor_order(local_summary, descriptors, permutation)
      call hash_descriptor_list(descriptors, permutation, local_hashes)

      reference_hashes = local_hashes
      call MPI_Bcast(reference_hashes, 2, mpi_int64_type, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_hash_mismatch = 0
      if (any(local_hashes /= reference_hashes)) local_hash_mismatch = 1

      call ftimer_mpi_allreduce(local_hash_mismatch, any_hash_mismatch, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      hashes_match = any_hash_mismatch == 0
#ifdef FTIMER_BUILD_TESTS
      test_preflight_after_descriptor_check = .true.
#endif

      if (.not. hashes_match) then
         ! Descriptor consistency is only meaningful after ranks have already
         ! agreed to enter the same communicator collective. Communicator
         ! disagreement across would-be participants is documented as unsupported.
         allocate (mismatch_flags(nprocs))
         call ftimer_mpi_allgather(local_hash_mismatch, 1, MPI_INTEGER, mismatch_flags, 1, MPI_INTEGER, active_comm, mpierr)
         if (mpierr /= MPI_SUCCESS) then
            status = FTIMER_ERR_UNKNOWN
            return
         end if
         if (present(diagnostic)) call format_descriptor_mismatch_diagnostic(mismatch_flags, diagnostic)
         status = FTIMER_ERR_MPI_INCON
         return
      end if

      call ftimer_mpi_allreduce(local_summary%total_time, min_total_time, 1, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_summary%total_time, max_total_time, 1, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_summary%total_time, sum_total_time, 1, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_min_total_rank = huge(local_min_total_rank)
      if (local_summary%total_time == min_total_time) local_min_total_rank = rank
      call ftimer_mpi_allreduce(local_min_total_rank, min_total_time_rank, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_max_total_rank = huge(local_max_total_rank)
      if (local_summary%total_time == max_total_time) local_max_total_rank = rank
      call ftimer_mpi_allreduce(local_max_total_rank, max_total_time_rank, 1, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      avg_total_time = sum_total_time/real(nprocs, wp)
      entry_count = local_summary%num_entries

      summary%num_ranks = nprocs
      summary%num_entries = entry_count
      summary%min_total_time = min_total_time
      summary%max_total_time = max_total_time
      summary%avg_total_time = avg_total_time
      summary%min_total_time_rank = min_total_time_rank
      summary%max_total_time_rank = max_total_time_rank
      summary%total_time_imbalance = compute_imbalance(max_total_time, avg_total_time)

      if (entry_count <= 0) then
         allocate (summary%entries(0))
         status = FTIMER_SUCCESS
         return
      end if

      allocate (local_inclusive(entry_count))
      allocate (min_inclusive(entry_count))
      allocate (max_inclusive(entry_count))
      allocate (sum_inclusive(entry_count))
      allocate (local_self(entry_count))
      allocate (min_self(entry_count))
      allocate (max_self(entry_count))
      allocate (sum_self(entry_count))
      allocate (local_pct(entry_count))
      allocate (min_pct(entry_count))
      allocate (max_pct(entry_count))
      allocate (sum_pct(entry_count))
      allocate (local_calls(entry_count))
      allocate (local_sum_calls(entry_count))
      allocate (min_calls(entry_count))
      allocate (max_calls(entry_count))
      allocate (sum_calls(entry_count))
      allocate (local_min_inclusive_ranks(entry_count))
      allocate (local_max_inclusive_ranks(entry_count))
      allocate (min_inclusive_ranks(entry_count))
      allocate (max_inclusive_ranks(entry_count))

      do i = 1, entry_count
         local_idx = permutation(i)
         local_inclusive(i) = local_summary%entries(local_idx)%inclusive_time
         local_self(i) = local_summary%entries(local_idx)%self_time
         local_calls(i) = local_summary%entries(local_idx)%call_count
         local_sum_calls(i) = int(local_calls(i), int64)
         local_pct(i) = local_summary%entries(local_idx)%pct_time
      end do

      call ftimer_mpi_allreduce(local_inclusive, min_inclusive, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_inclusive, max_inclusive, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_min_inclusive_ranks = huge(0)
      local_max_inclusive_ranks = huge(0)
      do i = 1, entry_count
         if (local_inclusive(i) == min_inclusive(i)) local_min_inclusive_ranks(i) = rank
         if (local_inclusive(i) == max_inclusive(i)) local_max_inclusive_ranks(i) = rank
      end do

      call ftimer_mpi_allreduce(local_min_inclusive_ranks, min_inclusive_ranks, entry_count, MPI_INTEGER, MPI_MIN, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_max_inclusive_ranks, max_inclusive_ranks, entry_count, MPI_INTEGER, MPI_MIN, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_inclusive, sum_inclusive, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self, min_self, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self, max_self, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self, sum_self, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct, min_pct, entry_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct, max_pct, entry_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct, sum_pct, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_calls, min_calls, entry_count, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_calls, max_calls, entry_count, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_sum_calls, sum_calls, entry_count, mpi_int64_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      max_node_id = 0
      do i = 1, entry_count
         max_node_id = max(max_node_id, local_summary%entries(i)%node_id)
      end do

      allocate (local_node_to_entry(max(max_node_id, 1)))
      allocate (local_entry_to_canonical(entry_count))
      local_node_to_entry = 0
      local_entry_to_canonical = 0

      do i = 1, entry_count
         if (local_summary%entries(i)%node_id > 0) then
            local_node_to_entry(local_summary%entries(i)%node_id) = i
         end if
      end do

      do i = 1, entry_count
         local_entry_to_canonical(permutation(i)) = i
      end do

      allocate (summary%entries(entry_count))
      do i = 1, entry_count
         local_idx = permutation(i)
         summary%entries(i)%name = local_summary%entries(local_idx)%name
         summary%entries(i)%depth = local_summary%entries(local_idx)%depth
         summary%entries(i)%node_id = i
         summary%entries(i)%parent_id = 0

         parent_id = local_summary%entries(local_idx)%parent_id
         if (parent_id > 0) then
            parent_entry = 0
            if (parent_id <= size(local_node_to_entry)) parent_entry = local_node_to_entry(parent_id)
            if (parent_entry > 0) summary%entries(i)%parent_id = local_entry_to_canonical(parent_entry)
         end if

         summary%entries(i)%min_inclusive_time = min_inclusive(i)
         summary%entries(i)%max_inclusive_time = max_inclusive(i)
         summary%entries(i)%avg_inclusive_time = sum_inclusive(i)/real(nprocs, wp)
         summary%entries(i)%min_inclusive_time_rank = min_inclusive_ranks(i)
         summary%entries(i)%max_inclusive_time_rank = max_inclusive_ranks(i)
         summary%entries(i)%inclusive_imbalance = compute_imbalance(max_inclusive(i), summary%entries(i)%avg_inclusive_time)
         summary%entries(i)%min_self_time = min_self(i)
         summary%entries(i)%max_self_time = max_self(i)
         summary%entries(i)%avg_self_time = sum_self(i)/real(nprocs, wp)
         summary%entries(i)%self_imbalance = compute_imbalance(max_self(i), summary%entries(i)%avg_self_time)
         summary%entries(i)%min_call_count = min_calls(i)
         summary%entries(i)%max_call_count = max_calls(i)
         summary%entries(i)%avg_call_count = real(sum_calls(i), wp)/real(nprocs, wp)
         summary%entries(i)%min_pct_time = min_pct(i)
         summary%entries(i)%max_pct_time = max_pct(i)
         summary%entries(i)%avg_pct_time = sum_pct(i)/real(nprocs, wp)
      end do

      status = FTIMER_SUCCESS
#else
      call clear_mpi_summary(summary)
      if (present(diagnostic)) diagnostic = ''
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine build_mpi_summary

   subroutine clear_mpi_summary(summary)
      type(ftimer_mpi_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_total_time = 0.0_wp
      summary%max_total_time = 0.0_wp
      summary%avg_total_time = 0.0_wp
      summary%min_total_time_rank = -1
      summary%max_total_time_rank = -1
      summary%total_time_imbalance = 1.0_wp
   end subroutine clear_mpi_summary

#ifdef FTIMER_USE_MPI
   subroutine resolve_mpi_summary_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
      integer, intent(out) :: mpi_wp_type
      integer, intent(out) :: mpi_int64_type
      integer, intent(out) :: status
      character(len=*), intent(out), optional :: diagnostic
      logical :: cleanup_ok
      integer :: int64_size
      integer :: mpierr
      integer :: reported_size
      integer :: saved_errhandler
      integer :: wp_size

      mpi_wp_type = MPI_DATATYPE_NULL
      mpi_int64_type = MPI_DATATYPE_NULL
      status = FTIMER_ERR_UNKNOWN
      cleanup_ok = .true.
      if (present(diagnostic)) diagnostic = ''

      wp_size = storage_size(1.0_wp)/8
      int64_size = storage_size(0_int64)/8
      if ((8*wp_size /= storage_size(1.0_wp)) .or. (8*int64_size /= storage_size(0_int64))) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary could not map real(wp) or integer(int64) storage to whole MPI datatype bytes"
         return
      end if

      call MPI_Comm_get_errhandler(MPI_COMM_SELF, saved_errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary could not inspect MPI_COMM_SELF error handler before datatype validation"
         return
      end if

      call MPI_Comm_set_errhandler(MPI_COMM_SELF, MPI_ERRORS_RETURN, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary could not enable MPI error returns before datatype validation"
         call free_mpi_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call MPI_Type_match_size(MPI_TYPECLASS_REAL, wp_size, mpi_wp_type, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_wp_type == MPI_DATATYPE_NULL)) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary could not find an MPI real datatype matching real(wp)"
         call restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call MPI_Type_size(mpi_wp_type, reported_size, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (reported_size /= wp_size)) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary MPI real datatype size does not match real(wp)"
         call restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call MPI_Type_match_size(MPI_TYPECLASS_INTEGER, int64_size, mpi_int64_type, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_int64_type == MPI_DATATYPE_NULL)) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary could not find an MPI integer datatype matching integer(int64)"
         call restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call MPI_Type_size(mpi_int64_type, reported_size, mpierr)
      if ((mpierr /= MPI_SUCCESS) .or. (reported_size /= int64_size)) then
         if (present(diagnostic)) diagnostic = &
            "ftimer mpi_summary MPI integer datatype size does not match integer(int64)"
         call restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
         return
      end if

      call restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
      if (.not. cleanup_ok) then
         return
      end if

      status = FTIMER_SUCCESS
   end subroutine resolve_mpi_summary_datatypes

   subroutine restore_mpi_comm_self_errhandler(saved_errhandler, cleanup_ok, diagnostic)
      integer, intent(inout) :: saved_errhandler
      logical, intent(out) :: cleanup_ok
      character(len=*), intent(inout), optional :: diagnostic
      character(len=256) :: original_diagnostic
      integer :: mpierr

      cleanup_ok = .true.
      original_diagnostic = ''
      if (present(diagnostic)) original_diagnostic = diagnostic
      call MPI_Comm_set_errhandler(MPI_COMM_SELF, saved_errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) cleanup_ok = .false.
      if ((mpierr /= MPI_SUCCESS) .and. present(diagnostic)) &
         call append_mpi_datatype_diagnostic(original_diagnostic, &
                                             "ftimer mpi_summary could not restore MPI_COMM_SELF error handler", &
                                             diagnostic)
      call free_mpi_errhandler(saved_errhandler, cleanup_ok, diagnostic)
   end subroutine restore_mpi_comm_self_errhandler

   subroutine free_mpi_errhandler(errhandler, cleanup_ok, diagnostic)
      integer, intent(inout) :: errhandler
      logical, intent(inout) :: cleanup_ok
      character(len=*), intent(inout), optional :: diagnostic
      character(len=256) :: original_diagnostic
      integer :: mpierr

      original_diagnostic = ''
      if (present(diagnostic)) original_diagnostic = diagnostic
      call MPI_Errhandler_free(errhandler, mpierr)
      if (mpierr /= MPI_SUCCESS) cleanup_ok = .false.
      if ((mpierr /= MPI_SUCCESS) .and. present(diagnostic)) &
         call append_mpi_datatype_diagnostic(original_diagnostic, &
                                             "ftimer mpi_summary could not free saved MPI error handler", &
                                             diagnostic)
   end subroutine free_mpi_errhandler

   subroutine append_mpi_datatype_diagnostic(original_diagnostic, cleanup_diagnostic, diagnostic)
      character(len=*), intent(in) :: original_diagnostic
      character(len=*), intent(in) :: cleanup_diagnostic
      character(len=*), intent(inout) :: diagnostic

      if (len_trim(original_diagnostic) > 0) then
         diagnostic = trim(original_diagnostic)//"; also "//trim(cleanup_diagnostic)
      else
         diagnostic = cleanup_diagnostic
      end if
   end subroutine append_mpi_datatype_diagnostic

   subroutine build_descriptor_order(summary, descriptors, permutation)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: descriptors(:)
      integer, allocatable, intent(out) :: permutation(:)
      character(len=:), allocatable :: component
      character(len=:), allocatable :: path_strings(:)
      integer :: component_len
      integer :: i
      integer :: max_len
      integer :: max_node_id
      integer, allocatable :: node_to_entry(:)
      integer :: parent_entry
      integer :: parent_id
      integer, allocatable :: prefix_lengths(:)

      if (summary%num_entries <= 0) then
         allocate (character(len=1) :: descriptors(0))
         allocate (permutation(0))
         return
      end if

      max_node_id = 0
      do i = 1, summary%num_entries
         max_node_id = max(max_node_id, summary%entries(i)%node_id)
      end do

      allocate (prefix_lengths(summary%num_entries))
      allocate (node_to_entry(max(max_node_id, 1)))
      prefix_lengths = 0
      node_to_entry = 0
      max_len = 1

      do i = 1, summary%num_entries
         if (summary%entries(i)%node_id > 0) then
            node_to_entry(summary%entries(i)%node_id) = i
         end if
      end do

      do i = 1, summary%num_entries
         parent_id = summary%entries(i)%parent_id
         component_len = descriptor_component_length(summary_entry_name(summary%entries(i)))
         if (parent_id <= 0) then
            prefix_lengths(i) = component_len
         else
            parent_entry = 0
            if (parent_id <= size(node_to_entry)) parent_entry = node_to_entry(parent_id)
            if (parent_entry > 0) then
               prefix_lengths(i) = prefix_lengths(parent_entry) + component_len
            else
               prefix_lengths(i) = component_len
            end if
         end if
         max_len = max(max_len, prefix_lengths(i))
      end do

      allocate (character(len=max_len) :: descriptors(summary%num_entries))
      allocate (character(len=max_len) :: path_strings(summary%num_entries))
      allocate (permutation(summary%num_entries))

      descriptors = ''
      path_strings = ''

      do i = 1, summary%num_entries
         parent_id = summary%entries(i)%parent_id
         call encode_descriptor_component(summary_entry_name(summary%entries(i)), component)
         component_len = len(component)
         if (parent_id <= 0) then
            path_strings(i) = component(1:component_len)
         else
            parent_entry = 0
            if (parent_id <= size(node_to_entry)) parent_entry = node_to_entry(parent_id)
            if (parent_entry > 0) then
               path_strings(i) = trim(path_strings(parent_entry))//component(1:component_len)
            else
               path_strings(i) = component(1:component_len)
            end if
         end if
         descriptors(i) = path_strings(i)
         permutation(i) = i
      end do

      call sort_permutation_by_descriptor(descriptors, permutation)
   end subroutine build_descriptor_order

   integer function descriptor_component_length(name) result(component_len)
      character(len=*), intent(in) :: name

      component_len = decimal_digit_count(len_trim(name)) + 1 + len_trim(name)
   end function descriptor_component_length

   subroutine encode_descriptor_component(name, component)
      character(len=*), intent(in) :: name
      character(len=:), allocatable, intent(out) :: component
      character(len=32) :: len_text
      integer :: trimmed_len

      trimmed_len = len_trim(name)

      write (len_text, '(i0)') trimmed_len
      if (trimmed_len > 0) then
         component = trim(len_text)//':'//name(1:trimmed_len)
      else
         component = trim(len_text)//':'
      end if
   end subroutine encode_descriptor_component

   integer function decimal_digit_count(value) result(count)
      integer, intent(in) :: value
      integer :: remaining

      count = 1
      remaining = value
      do while (remaining >= 10)
         remaining = remaining/10
         count = count + 1
      end do
   end function decimal_digit_count

   function summary_entry_name(entry) result(name)
      type(ftimer_summary_entry_t), intent(in) :: entry
      character(len=:), allocatable :: name

      if (allocated(entry%name)) then
         name = entry%name
      else
         name = ''
      end if
   end function summary_entry_name

   subroutine sort_permutation_by_descriptor(descriptors, permutation)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(inout) :: permutation(:)
      integer :: i
      integer :: j
      integer :: key

      do i = 2, size(permutation)
         key = permutation(i)
         j = i - 1
         do while (j >= 1)
            if (descriptors(permutation(j)) <= descriptors(key)) exit
            permutation(j + 1) = permutation(j)
            j = j - 1
         end do
         permutation(j + 1) = key
      end do
   end subroutine sort_permutation_by_descriptor

   subroutine hash_descriptor_list(descriptors, permutation, hash_values)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: permutation(:)
      integer(int64), intent(out) :: hash_values(2)
      integer :: i
      integer :: j
      integer :: trimmed_len
      integer(int64) :: high_hash
      integer(int64) :: low_hash

      high_hash = 2166136261_int64
      low_hash = 1315423911_int64

      high_hash = hash_step(high_hash, int(size(permutation), int64), 16777619_int64, 4294967291_int64)
      low_hash = hash_step(low_hash, int(size(permutation), int64), 65599_int64, 4294967279_int64)

      do i = 1, size(permutation)
         trimmed_len = len_trim(descriptors(permutation(i)))
         do j = 1, trimmed_len
            high_hash = hash_step(high_hash, int(iachar(descriptors(permutation(i)) (j:j)), int64), &
                                  16777619_int64, 4294967291_int64)
            low_hash = hash_step(low_hash, int(iachar(descriptors(permutation(i)) (j:j)), int64), &
                                 65599_int64, 4294967279_int64)
         end do
         high_hash = hash_step(high_hash, 10_int64, 16777619_int64, 4294967291_int64)
         low_hash = hash_step(low_hash, 10_int64, 65599_int64, 4294967279_int64)
      end do

      hash_values(1) = high_hash
      hash_values(2) = low_hash
   end subroutine hash_descriptor_list

   integer(int64) function hash_step(current, value, base, modulus) result(updated)
      integer(int64), intent(in) :: current
      integer(int64), intent(in) :: value
      integer(int64), intent(in) :: base
      integer(int64), intent(in) :: modulus

      updated = modulo(current*base + value, modulus)
   end function hash_step

   subroutine format_descriptor_mismatch_diagnostic(mismatch_flags, diagnostic)
      integer, intent(in) :: mismatch_flags(:)
      character(len=*), intent(out) :: diagnostic
      character(len=*), parameter :: base_message = "ftimer mpi_summary detected inconsistent timer descriptors "// &
                                     "across ranks in the init communicator"
      character(len=*), parameter :: rank_prefix = "; reference rank 0 differs from ranks "
      character(len=*), parameter :: truncated_message = "ftimer mpi_summary descriptor mismatch; "// &
                                     "disagreeing-rank list truncated"
      character(len=32) :: rank_text
      character(len=len(diagnostic)) :: rank_list
      character(len=34) :: rank_piece
      integer :: available_len
      integer :: i
      logical :: truncated

      diagnostic = base_message
      rank_list = ''
      truncated = .false.
      available_len = len(diagnostic) - len_trim(base_message) - len(rank_prefix)

      if (available_len < 3) then
         diagnostic = truncated_message
         return
      end if

      do i = 2, size(mismatch_flags)
         if (mismatch_flags(i) == 0) cycle
         write (rank_text, '(i0)') i - 1
         if (len_trim(rank_list) > 0) then
            rank_piece = ", "//trim(rank_text)
         else
            rank_piece = trim(rank_text)
         end if

         if (len_trim(rank_list) + len_trim(rank_piece) <= available_len) then
            rank_list = trim(rank_list)//trim(rank_piece)
         else
            truncated = .true.
            exit
         end if
      end do

      if (truncated) call mark_rank_list_truncated(rank_list, available_len)

      if (len_trim(rank_list) > 0) then
         diagnostic = trim(diagnostic)//rank_prefix//trim(rank_list)
      end if
   end subroutine format_descriptor_mismatch_diagnostic

   subroutine mark_rank_list_truncated(rank_list, available_len)
      character(len=*), intent(inout) :: rank_list
      integer, intent(in) :: available_len

      if (available_len < 3) then
         rank_list = ''
      else if (len_trim(rank_list) == 0) then
         rank_list = '...'
      else if (len_trim(rank_list) + 5 <= available_len) then
         rank_list = trim(rank_list)//", ..."
      else if (available_len == 3) then
         rank_list = '...'
      else
         rank_list = rank_list(1:available_len - 3)//'...'
      end if
   end subroutine mark_rank_list_truncated

   subroutine ftimer_mpi_allgather(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, comm, mpierr)
      integer, intent(in) :: sendbuf
      integer, intent(in) :: sendcount
      integer, intent(in) :: sendtype
      integer, intent(out) :: recvbuf(*)
      integer, intent(in) :: recvcount
      integer, intent(in) :: recvtype
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr
#ifdef FTIMER_BUILD_TESTS
      integer :: nvalues
      integer :: test_mpierr

      test_preflight_allgather_count = test_preflight_allgather_count + 1
      if ((sendcount == 1) .and. (recvcount == 1) .and. &
          (sendtype == MPI_INTEGER) .and. (recvtype == MPI_INTEGER)) then
         test_preflight_mismatch_flag_allgather_count = test_preflight_mismatch_flag_allgather_count + 1
      end if
#endif

      call MPI_Allgather(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, comm, mpierr)
#ifdef FTIMER_BUILD_TESTS
      if ((mpierr == MPI_SUCCESS) .and. (sendcount == 1) .and. (recvcount == 1) .and. &
          (sendtype == MPI_INTEGER) .and. (recvtype == MPI_INTEGER)) then
         if (allocated(test_preflight_mismatch_flags)) deallocate (test_preflight_mismatch_flags)
         call MPI_Comm_size(comm, nvalues, test_mpierr)
         if (test_mpierr == MPI_SUCCESS) then
            allocate (test_preflight_mismatch_flags(nvalues))
            test_preflight_mismatch_flags = recvbuf(1:nvalues)
         end if
      end if
#endif
   end subroutine ftimer_mpi_allgather

   subroutine ftimer_mpi_allreduce_integer_scalar(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      integer, intent(in) :: sendbuf
      integer, intent(out) :: recvbuf
      integer, intent(in) :: count
      integer, intent(in) :: datatype
      integer, intent(in) :: op
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_integer_scalar

   subroutine ftimer_mpi_allreduce_integer_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      integer, intent(in) :: sendbuf(:)
      integer, intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      integer, intent(in) :: datatype
      integer, intent(in) :: op
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_integer_array

   subroutine ftimer_mpi_allreduce_int64_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      integer(int64), intent(in) :: sendbuf(:)
      integer(int64), intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      integer, intent(in) :: datatype
      integer, intent(in) :: op
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_int64_array

   subroutine ftimer_mpi_allreduce_real_scalar(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      real(wp), intent(in) :: sendbuf
      real(wp), intent(out) :: recvbuf
      integer, intent(in) :: count
      integer, intent(in) :: datatype
      integer, intent(in) :: op
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_real_scalar

   subroutine ftimer_mpi_allreduce_real_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      real(wp), intent(in) :: sendbuf(:)
      real(wp), intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      integer, intent(in) :: datatype
      integer, intent(in) :: op
      integer, intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_real_array

   subroutine ftimer_test_note_summary_reduction_phase()
#ifdef FTIMER_BUILD_TESTS
      if (test_preflight_after_descriptor_check) test_preflight_summary_reduction_count = 1
#endif
   end subroutine ftimer_test_note_summary_reduction_phase

#ifdef FTIMER_BUILD_TESTS
   subroutine ftimer_test_reset_mpi_preflight_collectives()
      test_preflight_allgather_count = 0
      test_preflight_mismatch_flag_allgather_count = 0
      test_preflight_summary_reduction_count = 0
      test_preflight_after_descriptor_check = .false.
      if (allocated(test_preflight_mismatch_flags)) deallocate (test_preflight_mismatch_flags)
   end subroutine ftimer_test_reset_mpi_preflight_collectives

   subroutine ftimer_test_get_mpi_preflight_collectives(allgather_count, mismatch_flag_allgather_count, &
                                                        summary_reduction_count)
      integer, intent(out) :: allgather_count
      integer, intent(out) :: mismatch_flag_allgather_count
      integer, intent(out) :: summary_reduction_count

      allgather_count = test_preflight_allgather_count
      mismatch_flag_allgather_count = test_preflight_mismatch_flag_allgather_count
      summary_reduction_count = test_preflight_summary_reduction_count
   end subroutine ftimer_test_get_mpi_preflight_collectives

   subroutine ftimer_test_get_mpi_preflight_mismatch_flags(mismatch_flags)
      integer, allocatable, intent(out) :: mismatch_flags(:)

      if (allocated(test_preflight_mismatch_flags)) then
         allocate (mismatch_flags(size(test_preflight_mismatch_flags)))
         mismatch_flags = test_preflight_mismatch_flags
      else
         allocate (mismatch_flags(0))
      end if
   end subroutine ftimer_test_get_mpi_preflight_mismatch_flags

#endif
#endif

   real(wp) function compute_imbalance(max_time, avg_time) result(imbalance)
      real(wp), intent(in) :: max_time
      real(wp), intent(in) :: avg_time

      if (abs(avg_time) <= tiny(1.0_wp)) then
         if (abs(max_time) <= tiny(1.0_wp)) then
            imbalance = 1.0_wp
         else
            imbalance = 0.0_wp
         end if
         return
      end if

      imbalance = max_time/avg_time
   end function compute_imbalance

end module ftimer_mpi
