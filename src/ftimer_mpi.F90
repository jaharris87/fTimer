module ftimer_mpi
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, &
                           FTIMER_ERR_UNKNOWN, FTIMER_SUCCESS, ftimer_mpi_summary_t, ftimer_mpi_union_summary_t, &
                           ftimer_summary_entry_t, ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi_f08, only: MPI_Allgather, MPI_Allreduce, MPI_Bcast, MPI_CHARACTER, MPI_Comm, MPI_COMM_NULL, &
                      MPI_COMM_SELF, MPI_COMM_WORLD, MPI_Datatype, MPI_DATATYPE_NULL, MPI_Errhandler, &
                      MPI_ERRORS_RETURN, MPI_INTEGER, MPI_MAX, MPI_MIN, MPI_Op, MPI_SUCCESS, MPI_SUM, &
                      MPI_TYPECLASS_INTEGER, MPI_TYPECLASS_REAL, MPI_Comm_get_errhandler, MPI_Comm_rank, &
                      MPI_Comm_set_errhandler, MPI_Comm_size, MPI_Errhandler_free, MPI_Type_match_size, &
                      MPI_Type_size
#endif
   implicit none
   private

   public :: build_mpi_summary
   public :: build_mpi_union_summary
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
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
      type(MPI_Comm), intent(out) :: active_comm
#else
      integer, intent(in), optional :: comm
      integer, intent(out) :: active_comm
#endif
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      ! Contract: mpi_summary() is collective over the communicator captured at init.
      ! If init omitted `comm`, ftimer_core omits it here and mpi_summary()
      ! resolves that contract to MPI_COMM_WORLD.
      active_comm = MPI_COMM_WORLD
      if (present(comm)) active_comm = comm

      if (active_comm%MPI_VAL == MPI_COMM_NULL%MPI_VAL) then
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
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
      type(MPI_Comm), intent(out) :: active_comm
#else
      integer, intent(in), optional :: comm
      integer, intent(out) :: active_comm
#endif
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
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
#else
      integer, intent(in), optional :: comm
#endif
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
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
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
#else
      integer, intent(in), optional :: comm
#endif
      type(ftimer_mpi_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out), optional :: diagnostic
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
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
      integer :: mpierr
      integer :: nprocs
      integer :: parent_entry
      integer :: parent_id
      integer :: rank
      type(MPI_Datatype) :: mpi_int64_type
      type(MPI_Datatype) :: mpi_wp_type
      integer, allocatable :: local_entry_to_canonical(:)
      integer, allocatable :: local_max_inclusive_ranks(:)
      integer, allocatable :: local_min_inclusive_ranks(:)
      integer, allocatable :: local_node_to_entry(:)
      integer, allocatable :: max_inclusive_ranks(:)
      integer, allocatable :: min_inclusive_ranks(:)
      integer, allocatable :: mismatch_flags(:)
      integer, allocatable :: permutation(:)
      integer(int64), allocatable :: local_calls(:)
      integer(int64), allocatable :: max_calls(:)
      integer(int64), allocatable :: min_calls(:)
      integer(int64) :: local_hashes(2)
      integer(int64) :: reference_hashes(2)
      integer :: any_hash_mismatch
      integer :: local_hash_mismatch
      real(wp) :: avg_total_time
      real(wp) :: max_total_time
      real(wp) :: min_total_time
      real(wp) :: sum_total_time
      real(wp), allocatable :: local_inclusive(:)
      real(wp), allocatable :: local_call_avg(:)
      real(wp), allocatable :: local_pct(:)
      real(wp), allocatable :: local_self(:)
      real(wp), allocatable :: max_inclusive(:)
      real(wp), allocatable :: max_pct(:)
      real(wp), allocatable :: max_self(:)
      real(wp), allocatable :: min_inclusive(:)
      real(wp), allocatable :: min_pct(:)
      real(wp), allocatable :: min_self(:)
      real(wp), allocatable :: sum_call_avg(:)
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
      allocate (min_calls(entry_count))
      allocate (max_calls(entry_count))
      allocate (local_call_avg(entry_count))
      allocate (sum_call_avg(entry_count))
      allocate (local_min_inclusive_ranks(entry_count))
      allocate (local_max_inclusive_ranks(entry_count))
      allocate (min_inclusive_ranks(entry_count))
      allocate (max_inclusive_ranks(entry_count))

      do i = 1, entry_count
         local_idx = permutation(i)
         local_inclusive(i) = local_summary%entries(local_idx)%inclusive_time
         local_self(i) = local_summary%entries(local_idx)%self_time
         local_calls(i) = local_summary%entries(local_idx)%call_count
         local_call_avg(i) = call_count_average_operand(local_summary%entries(local_idx)%call_count)
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

      call ftimer_mpi_allreduce(local_calls, min_calls, entry_count, mpi_int64_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_calls, max_calls, entry_count, mpi_int64_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_call_avg, sum_call_avg, entry_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
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
         summary%entries(i)%avg_call_count = sum_call_avg(i)/real(nprocs, wp)
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

   subroutine build_mpi_union_summary(local_summary, comm, summary, status, diagnostic)
      type(ftimer_summary_t), intent(in) :: local_summary
#ifdef FTIMER_USE_MPI
      type(MPI_Comm), intent(in), optional :: comm
#else
      integer, intent(in), optional :: comm
#endif
      type(ftimer_mpi_union_summary_t), intent(out) :: summary
      integer, intent(out) :: status
      character(len=*), intent(out), optional :: diagnostic
#ifdef FTIMER_USE_MPI
      type(MPI_Comm) :: active_comm
      integer :: all_datatypes_ready
      integer :: entry_count
      integer :: datatypes_ready
      integer :: i
      integer :: local_descriptor_count
      integer :: local_idx
      integer :: local_max_descriptor_len
      integer :: local_max_total_rank
      integer :: local_min_total_rank
      integer :: max_descriptor_count
      integer :: max_descriptor_len
      integer :: max_total_time_rank
      integer :: min_total_time_rank
      integer :: mpierr
      integer :: nprocs
      integer :: parent_id
      integer :: rank
      integer :: union_count
      integer :: union_idx
      type(MPI_Datatype) :: mpi_int64_type
      type(MPI_Datatype) :: mpi_wp_type
      character(len=:), allocatable :: descriptors(:)
      character(len=:), allocatable :: entry_name
      character(len=:), allocatable :: parent_descriptor
      character(len=:), allocatable :: union_descriptors(:)
      integer, allocatable :: local_max_inclusive_ranks(:)
      integer, allocatable :: local_min_inclusive_ranks(:)
      integer, allocatable :: local_present(:)
      integer, allocatable :: local_to_union(:)
      integer, allocatable :: max_inclusive_ranks(:)
      integer, allocatable :: min_inclusive_ranks(:)
      integer, allocatable :: participating_counts(:)
      integer, allocatable :: permutation(:)
      integer(int64), allocatable :: local_calls_max(:)
      integer(int64), allocatable :: local_calls_min(:)
      integer(int64), allocatable :: max_calls(:)
      integer(int64), allocatable :: min_calls(:)
      real(wp) :: avg_total_time
      real(wp) :: max_total_time
      real(wp) :: min_total_time
      real(wp) :: sum_total_time
      real(wp), allocatable :: local_avg_calls(:)
      real(wp), allocatable :: local_inclusive_max(:)
      real(wp), allocatable :: local_inclusive_min(:)
      real(wp), allocatable :: local_inclusive_sum(:)
      real(wp), allocatable :: local_pct_max(:)
      real(wp), allocatable :: local_pct_min(:)
      real(wp), allocatable :: local_pct_sum(:)
      real(wp), allocatable :: local_self_max(:)
      real(wp), allocatable :: local_self_min(:)
      real(wp), allocatable :: local_self_sum(:)
      real(wp), allocatable :: max_inclusive(:)
      real(wp), allocatable :: max_pct(:)
      real(wp), allocatable :: max_self(:)
      real(wp), allocatable :: min_inclusive(:)
      real(wp), allocatable :: min_pct(:)
      real(wp), allocatable :: min_self(:)
      real(wp), allocatable :: sum_avg_calls(:)
      real(wp), allocatable :: sum_inclusive(:)
      real(wp), allocatable :: sum_pct(:)
      real(wp), allocatable :: sum_self(:)

      call clear_mpi_union_summary(summary)
      if (present(diagnostic)) diagnostic = ''

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
               "ftimer mpi_union_summary datatype validation failed on another rank"
         end if
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

      entry_count = local_summary%num_entries
      call build_descriptor_order(local_summary, descriptors, permutation)

      local_descriptor_count = size(permutation)
      local_max_descriptor_len = 1
      do i = 1, local_descriptor_count
         local_max_descriptor_len = max(local_max_descriptor_len, len_trim(descriptors(permutation(i))))
      end do

      call ftimer_mpi_allreduce(local_descriptor_count, max_descriptor_count, 1, MPI_INTEGER, MPI_MAX, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_max_descriptor_len, max_descriptor_len, 1, MPI_INTEGER, MPI_MAX, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call build_union_descriptor_list(descriptors, permutation, max_descriptor_count, max_descriptor_len, &
                                       nprocs, active_comm, union_descriptors, union_count, local_to_union, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      avg_total_time = sum_total_time/real(nprocs, wp)
      summary%num_ranks = nprocs
      summary%num_entries = union_count
      summary%min_total_time = min_total_time
      summary%max_total_time = max_total_time
      summary%avg_total_time = avg_total_time
      summary%min_total_time_rank = min_total_time_rank
      summary%max_total_time_rank = max_total_time_rank
      summary%total_time_imbalance = compute_imbalance(max_total_time, avg_total_time)

      if (union_count <= 0) then
         allocate (summary%entries(0))
         status = FTIMER_SUCCESS
         return
      end if

      allocate (local_present(union_count))
      allocate (participating_counts(union_count))
      allocate (local_inclusive_min(union_count))
      allocate (local_inclusive_max(union_count))
      allocate (local_inclusive_sum(union_count))
      allocate (min_inclusive(union_count))
      allocate (max_inclusive(union_count))
      allocate (sum_inclusive(union_count))
      allocate (local_self_min(union_count))
      allocate (local_self_max(union_count))
      allocate (local_self_sum(union_count))
      allocate (min_self(union_count))
      allocate (max_self(union_count))
      allocate (sum_self(union_count))
      allocate (local_pct_min(union_count))
      allocate (local_pct_max(union_count))
      allocate (local_pct_sum(union_count))
      allocate (min_pct(union_count))
      allocate (max_pct(union_count))
      allocate (sum_pct(union_count))
      allocate (local_calls_min(union_count))
      allocate (local_calls_max(union_count))
      allocate (min_calls(union_count))
      allocate (max_calls(union_count))
      allocate (local_avg_calls(union_count))
      allocate (sum_avg_calls(union_count))
      allocate (local_min_inclusive_ranks(union_count))
      allocate (local_max_inclusive_ranks(union_count))
      allocate (min_inclusive_ranks(union_count))
      allocate (max_inclusive_ranks(union_count))

      local_present = 0
      local_inclusive_min = huge(1.0_wp)
      local_inclusive_max = -huge(1.0_wp)
      local_inclusive_sum = 0.0_wp
      local_self_min = huge(1.0_wp)
      local_self_max = -huge(1.0_wp)
      local_self_sum = 0.0_wp
      local_pct_min = huge(1.0_wp)
      local_pct_max = -huge(1.0_wp)
      local_pct_sum = 0.0_wp
      local_calls_min = huge(0_int64)
      local_calls_max = -huge(0_int64)
      local_avg_calls = 0.0_wp

      do i = 1, entry_count
         union_idx = local_to_union(i)
         if (union_idx <= 0) cycle
         local_idx = permutation(i)
         local_present(union_idx) = 1
         local_inclusive_min(union_idx) = local_summary%entries(local_idx)%inclusive_time
         local_inclusive_max(union_idx) = local_summary%entries(local_idx)%inclusive_time
         local_inclusive_sum(union_idx) = local_summary%entries(local_idx)%inclusive_time
         local_self_min(union_idx) = local_summary%entries(local_idx)%self_time
         local_self_max(union_idx) = local_summary%entries(local_idx)%self_time
         local_self_sum(union_idx) = local_summary%entries(local_idx)%self_time
         local_pct_min(union_idx) = local_summary%entries(local_idx)%pct_time
         local_pct_max(union_idx) = local_summary%entries(local_idx)%pct_time
         local_pct_sum(union_idx) = local_summary%entries(local_idx)%pct_time
         local_calls_min(union_idx) = local_summary%entries(local_idx)%call_count
         local_calls_max(union_idx) = local_summary%entries(local_idx)%call_count
         local_avg_calls(union_idx) = call_count_average_operand(local_summary%entries(local_idx)%call_count)
      end do

      call ftimer_mpi_allreduce(local_present, participating_counts, union_count, MPI_INTEGER, MPI_SUM, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_inclusive_min, min_inclusive, union_count, mpi_wp_type, MPI_MIN, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_inclusive_max, max_inclusive, union_count, mpi_wp_type, MPI_MAX, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      local_min_inclusive_ranks = huge(0)
      local_max_inclusive_ranks = huge(0)
      do i = 1, union_count
         if ((local_present(i) == 1) .and. (local_inclusive_min(i) == min_inclusive(i))) &
            local_min_inclusive_ranks(i) = rank
         if ((local_present(i) == 1) .and. (local_inclusive_max(i) == max_inclusive(i))) &
            local_max_inclusive_ranks(i) = rank
      end do

      call ftimer_mpi_allreduce(local_min_inclusive_ranks, min_inclusive_ranks, union_count, MPI_INTEGER, &
                                MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_max_inclusive_ranks, max_inclusive_ranks, union_count, MPI_INTEGER, &
                                MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_inclusive_sum, sum_inclusive, union_count, mpi_wp_type, MPI_SUM, &
                                active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self_min, min_self, union_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self_max, max_self, union_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_self_sum, sum_self, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct_min, min_pct, union_count, mpi_wp_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct_max, max_pct, union_count, mpi_wp_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_pct_sum, sum_pct, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_calls_min, min_calls, union_count, mpi_int64_type, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_calls_max, max_calls, union_count, mpi_int64_type, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call ftimer_mpi_allreduce(local_avg_calls, sum_avg_calls, union_count, mpi_wp_type, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_union_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (summary%entries(union_count))
      do i = 1, union_count
         call decode_descriptor_metadata(union_descriptors(i), entry_name, parent_descriptor, summary%entries(i)%depth)
         parent_id = 0
         if (len_trim(parent_descriptor) > 0) parent_id = find_descriptor_index(union_descriptors, union_count, &
                                                                                parent_descriptor)

         summary%entries(i)%name = entry_name
         summary%entries(i)%node_id = i
         summary%entries(i)%parent_id = parent_id
         summary%entries(i)%participating_rank_count = participating_counts(i)

         if (participating_counts(i) > 0) then
            summary%entries(i)%min_inclusive_time = min_inclusive(i)
            summary%entries(i)%max_inclusive_time = max_inclusive(i)
            summary%entries(i)%avg_inclusive_time = sum_inclusive(i)/real(participating_counts(i), wp)
            summary%entries(i)%min_inclusive_time_rank = min_inclusive_ranks(i)
            summary%entries(i)%max_inclusive_time_rank = max_inclusive_ranks(i)
            summary%entries(i)%inclusive_imbalance = compute_imbalance(max_inclusive(i), &
                                                                       summary%entries(i)%avg_inclusive_time)
            summary%entries(i)%min_self_time = min_self(i)
            summary%entries(i)%max_self_time = max_self(i)
            summary%entries(i)%avg_self_time = sum_self(i)/real(participating_counts(i), wp)
            summary%entries(i)%self_imbalance = compute_imbalance(max_self(i), summary%entries(i)%avg_self_time)
            summary%entries(i)%min_call_count = min_calls(i)
            summary%entries(i)%max_call_count = max_calls(i)
            summary%entries(i)%avg_call_count = sum_avg_calls(i)/real(participating_counts(i), wp)
            summary%entries(i)%min_pct_time = min_pct(i)
            summary%entries(i)%max_pct_time = max_pct(i)
            summary%entries(i)%avg_pct_time = sum_pct(i)/real(participating_counts(i), wp)
         end if
      end do

      status = FTIMER_SUCCESS
#else
      call clear_mpi_union_summary(summary)
      if (present(diagnostic)) diagnostic = ''
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine build_mpi_union_summary

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

   subroutine clear_mpi_union_summary(summary)
      type(ftimer_mpi_union_summary_t), intent(out) :: summary

      if (allocated(summary%entries)) deallocate (summary%entries)
      summary%num_ranks = 0
      summary%num_entries = 0
      summary%min_total_time = 0.0_wp
      summary%max_total_time = 0.0_wp
      summary%avg_total_time = 0.0_wp
      summary%min_total_time_rank = -1
      summary%max_total_time_rank = -1
      summary%total_time_imbalance = 1.0_wp
   end subroutine clear_mpi_union_summary

#ifdef FTIMER_USE_MPI
   logical function checked_multiply_int(lhs, rhs, product) result(ok)
      integer, intent(in) :: lhs
      integer, intent(in) :: rhs
      integer, intent(out) :: product
      integer(int64) :: wide_product

      ok = .false.
      product = 0
      if ((lhs < 0) .or. (rhs < 0)) return

      wide_product = int(lhs, int64)*int(rhs, int64)
      if (wide_product > int(huge(product), int64)) return

      product = int(wide_product)
      ok = .true.
   end function checked_multiply_int

   subroutine build_union_descriptor_list(descriptors, permutation, max_descriptor_count, max_descriptor_len, &
                                          nprocs, active_comm, union_descriptors, union_count, local_to_union, mpierr)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: permutation(:)
      integer, intent(in) :: max_descriptor_count
      integer, intent(in) :: max_descriptor_len
      integer, intent(in) :: nprocs
      type(MPI_Comm), intent(in) :: active_comm
      character(len=:), allocatable, intent(out) :: union_descriptors(:)
      integer, intent(out) :: union_count
      integer, allocatable, intent(out) :: local_to_union(:)
      integer, intent(out) :: mpierr
      character(len=max_descriptor_len) :: descriptor_value
      character(len=1), allocatable :: all_descriptor_chars(:)
      character(len=1), allocatable :: local_descriptor_chars(:)
      integer :: char_count
      integer :: descriptor_len
      integer :: i
      integer :: j
      integer :: local_idx
      integer :: offset
      integer :: rank_slot
      integer :: slot
      integer :: union_capacity
      integer, allocatable :: all_descriptor_lengths(:)
      integer, allocatable :: local_descriptor_lengths(:)

      allocate (local_to_union(size(permutation)))
      local_to_union = 0
      union_count = 0
      mpierr = MPI_SUCCESS

      if (max_descriptor_count <= 0) then
         allocate (character(len=1) :: union_descriptors(0))
         return
      end if

      if (.not. checked_multiply_int(max_descriptor_count, nprocs, union_capacity)) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if

      if (.not. checked_multiply_int(max_descriptor_count, max_descriptor_len, char_count)) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (character(len=max_descriptor_len) :: union_descriptors(union_capacity))
      union_descriptors = ''

      allocate (local_descriptor_lengths(max_descriptor_count))
      allocate (all_descriptor_lengths(union_capacity))
      local_descriptor_lengths = 0

      if (.not. checked_multiply_int(char_count, nprocs, union_capacity)) then
         mpierr = FTIMER_ERR_UNKNOWN
         return
      end if

      allocate (local_descriptor_chars(char_count))
      allocate (all_descriptor_chars(union_capacity))
      local_descriptor_chars = ' '

      do i = 1, size(permutation)
         local_idx = permutation(i)
         descriptor_len = len_trim(descriptors(local_idx))
         local_descriptor_lengths(i) = descriptor_len
         offset = (i - 1)*max_descriptor_len
         do j = 1, descriptor_len
            local_descriptor_chars(offset + j) = descriptors(local_idx) (j:j)
         end do
      end do

      call MPI_Allgather(local_descriptor_lengths, max_descriptor_count, MPI_INTEGER, &
                         all_descriptor_lengths, max_descriptor_count, MPI_INTEGER, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return

      call MPI_Allgather(local_descriptor_chars, char_count, MPI_CHARACTER, &
                         all_descriptor_chars, char_count, MPI_CHARACTER, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) return

      do rank_slot = 1, nprocs
         do slot = 1, max_descriptor_count
            descriptor_len = all_descriptor_lengths((rank_slot - 1)*max_descriptor_count + slot)
            if (descriptor_len <= 0) cycle

            descriptor_value = ''
            offset = ((rank_slot - 1)*char_count) + (slot - 1)*max_descriptor_len
            do j = 1, descriptor_len
               descriptor_value(j:j) = all_descriptor_chars(offset + j)
            end do
            call add_union_descriptor(descriptor_value, union_descriptors, union_count)
         end do
      end do

      do i = 1, size(permutation)
         local_to_union(i) = find_descriptor_index(union_descriptors, union_count, descriptors(permutation(i)))
      end do
   end subroutine build_union_descriptor_list

   subroutine add_union_descriptor(descriptor, union_descriptors, union_count)
      character(len=*), intent(in) :: descriptor
      character(len=*), intent(inout) :: union_descriptors(:)
      integer, intent(inout) :: union_count
      integer :: insert_pos
      integer :: j

      insert_pos = union_count + 1
      do j = 1, union_count
         if (descriptor == union_descriptors(j)) return
         if (descriptor < union_descriptors(j)) then
            insert_pos = j
            exit
         end if
      end do

      union_count = union_count + 1
      do j = union_count, insert_pos + 1, -1
         union_descriptors(j) = union_descriptors(j - 1)
      end do
      union_descriptors(insert_pos) = descriptor
   end subroutine add_union_descriptor

   integer function find_descriptor_index(descriptors, descriptor_count, descriptor) result(index_value)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: descriptor_count
      character(len=*), intent(in) :: descriptor
      integer :: i

      index_value = 0
      do i = 1, descriptor_count
         if (descriptors(i) == descriptor) then
            index_value = i
            return
         end if
      end do
   end function find_descriptor_index

   subroutine decode_descriptor_metadata(descriptor, name, parent_descriptor, depth)
      character(len=*), intent(in) :: descriptor
      character(len=:), allocatable, intent(out) :: name
      character(len=:), allocatable, intent(out) :: parent_descriptor
      integer, intent(out) :: depth
      integer :: component_count
      integer :: component_start
      integer :: last_component_start
      integer :: last_name_len
      integer :: last_name_start
      integer :: name_len
      integer :: name_start
      integer :: next_pos
      integer :: pos
      integer :: text_len

      name = ''
      parent_descriptor = ''
      depth = 0
      text_len = len_trim(descriptor)
      pos = 1
      component_count = 0
      last_component_start = 1
      last_name_start = 1
      last_name_len = 0

      do while (pos <= text_len)
         component_start = pos
         if (.not. parse_descriptor_component(descriptor, pos, text_len, name_start, name_len, next_pos)) then
            name = ''
            parent_descriptor = ''
            depth = 0
            return
         end if

         component_count = component_count + 1
         last_component_start = component_start
         last_name_start = name_start
         last_name_len = name_len
         pos = next_pos
      end do

      depth = max(component_count - 1, 0)
      if (last_name_len > 0) name = descriptor(last_name_start:last_name_start + last_name_len - 1)
      if (last_component_start > 1) parent_descriptor = descriptor(1:last_component_start - 1)
   end subroutine decode_descriptor_metadata

   logical function parse_descriptor_component(descriptor, start_pos, text_len, name_start, name_len, &
                                               next_pos) result(is_valid)
      character(len=*), intent(in) :: descriptor
      integer, intent(in) :: start_pos
      integer, intent(in) :: text_len
      integer, intent(out) :: name_start
      integer, intent(out) :: name_len
      integer, intent(out) :: next_pos
      integer :: colon_offset
      integer :: colon_pos
      integer :: io

      is_valid = .false.
      name_start = start_pos
      name_len = 0
      next_pos = start_pos
      if (start_pos > text_len) return

      colon_offset = index(descriptor(start_pos:text_len), ':')
      if (colon_offset <= 0) return

      colon_pos = start_pos + colon_offset - 1
      if (colon_pos <= start_pos) return
      read (descriptor(start_pos:colon_pos - 1), *, iostat=io) name_len
      if (io /= 0) return
      if (name_len < 0) return

      name_start = colon_pos + 1
      next_pos = name_start + name_len
      if (next_pos - 1 > text_len) return

      is_valid = .true.
   end function parse_descriptor_component

   subroutine resolve_mpi_summary_datatypes(mpi_wp_type, mpi_int64_type, status, diagnostic)
      type(MPI_Datatype), intent(out) :: mpi_wp_type
      type(MPI_Datatype), intent(out) :: mpi_int64_type
      integer, intent(out) :: status
      character(len=*), intent(out), optional :: diagnostic
      logical :: cleanup_ok
      integer :: int64_size
      integer :: mpierr
      integer :: reported_size
      type(MPI_Errhandler) :: saved_errhandler
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
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_wp_type%MPI_VAL == MPI_DATATYPE_NULL%MPI_VAL)) then
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
      if ((mpierr /= MPI_SUCCESS) .or. (mpi_int64_type%MPI_VAL == MPI_DATATYPE_NULL%MPI_VAL)) then
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
      type(MPI_Errhandler), intent(inout) :: saved_errhandler
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
      type(MPI_Errhandler), intent(inout) :: errhandler
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
      type(MPI_Datatype), intent(in) :: sendtype
      integer, intent(out) :: recvbuf(*)
      integer, intent(in) :: recvcount
      type(MPI_Datatype), intent(in) :: recvtype
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out) :: mpierr
#ifdef FTIMER_BUILD_TESTS
      integer :: nvalues
      integer :: test_mpierr

      test_preflight_allgather_count = test_preflight_allgather_count + 1
      if ((sendcount == 1) .and. (recvcount == 1) .and. &
          (sendtype%MPI_VAL == MPI_INTEGER%MPI_VAL) .and. (recvtype%MPI_VAL == MPI_INTEGER%MPI_VAL)) then
         test_preflight_mismatch_flag_allgather_count = test_preflight_mismatch_flag_allgather_count + 1
      end if
#endif

      call MPI_Allgather(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, comm, mpierr)
#ifdef FTIMER_BUILD_TESTS
      if ((mpierr == MPI_SUCCESS) .and. (sendcount == 1) .and. (recvcount == 1) .and. &
          (sendtype%MPI_VAL == MPI_INTEGER%MPI_VAL) .and. (recvtype%MPI_VAL == MPI_INTEGER%MPI_VAL)) then
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
      type(MPI_Datatype), intent(in) :: datatype
      type(MPI_Op), intent(in) :: op
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_integer_scalar

   subroutine ftimer_mpi_allreduce_integer_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      integer, intent(in) :: sendbuf(:)
      integer, intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      type(MPI_Datatype), intent(in) :: datatype
      type(MPI_Op), intent(in) :: op
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_integer_array

   subroutine ftimer_mpi_allreduce_int64_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      integer(int64), intent(in) :: sendbuf(:)
      integer(int64), intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      type(MPI_Datatype), intent(in) :: datatype
      type(MPI_Op), intent(in) :: op
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_int64_array

   subroutine ftimer_mpi_allreduce_real_scalar(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      real(wp), intent(in) :: sendbuf
      real(wp), intent(out) :: recvbuf
      integer, intent(in) :: count
      type(MPI_Datatype), intent(in) :: datatype
      type(MPI_Op), intent(in) :: op
      type(MPI_Comm), intent(in) :: comm
      integer, intent(out) :: mpierr

      call ftimer_test_note_summary_reduction_phase()
      call MPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
   end subroutine ftimer_mpi_allreduce_real_scalar

   subroutine ftimer_mpi_allreduce_real_array(sendbuf, recvbuf, count, datatype, op, comm, mpierr)
      real(wp), intent(in) :: sendbuf(:)
      real(wp), intent(out) :: recvbuf(:)
      integer, intent(in) :: count
      type(MPI_Datatype), intent(in) :: datatype
      type(MPI_Op), intent(in) :: op
      type(MPI_Comm), intent(in) :: comm
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

   real(wp) function call_count_average_operand(count) result(value)
      integer(int64), intent(in) :: count
      integer :: exponent
      integer :: i
      integer :: spacing_power
      integer(int64) :: floored_count
      integer(int64) :: scaled
      integer(int64) :: spacing

      if (count <= 0_int64) then
         value = 0.0_wp
         return
      end if

      scaled = count
      exponent = 0
      do while (scaled >= 2_int64)
         scaled = scaled/2_int64
         exponent = exponent + 1
      end do

      spacing_power = exponent - digits(1.0_wp) + 1
      if (spacing_power <= 0) then
         value = real(count, wp)
         return
      end if

      spacing = 1_int64
      do i = 1, spacing_power
         spacing = spacing*2_int64
      end do

      floored_count = count - modulo(count, spacing)
      value = real(floored_count, wp)
   end function call_count_average_operand

end module ftimer_mpi
