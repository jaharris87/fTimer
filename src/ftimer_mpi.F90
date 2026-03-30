module ftimer_mpi
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: FTIMER_ERR_ACTIVE, FTIMER_ERR_MPI_INCON, FTIMER_ERR_NOT_IMPLEMENTED, &
                           FTIMER_ERR_UNKNOWN, FTIMER_NAME_LEN, FTIMER_SUCCESS, ftimer_mpi_summary_t, &
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

      call MPI_Allreduce(local_active, any_active, 1, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      if (any_active /= 0) status = FTIMER_ERR_ACTIVE
#else
      status = FTIMER_ERR_NOT_IMPLEMENTED
#endif
   end subroutine check_mpi_summary_prereqs

   subroutine build_mpi_summary(local_summary, comm, summary, status)
      type(ftimer_summary_t), intent(in) :: local_summary
      integer, intent(in) :: comm
      type(ftimer_mpi_summary_t), intent(out) :: summary
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      integer :: active_comm
      integer :: entry_count
      integer :: i
      integer :: local_idx
      integer :: max_node_id
      integer :: mpierr
      integer :: nprocs
      integer :: parent_entry
      integer :: parent_id
      integer :: rank
      integer, allocatable :: local_calls(:)
      integer, allocatable :: local_entry_to_canonical(:)
      integer, allocatable :: local_node_to_entry(:)
      integer, allocatable :: max_calls(:)
      integer, allocatable :: min_calls(:)
      integer, allocatable :: permutation(:)
      integer, allocatable :: sum_calls(:)
      integer(int64) :: local_hashes(2)
      integer(int64), allocatable :: gathered_hashes(:, :)
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

      call get_mpi_summary_comm_info(comm, active_comm, rank, nprocs, status)
      if (status /= FTIMER_SUCCESS) return

      call build_descriptor_order(local_summary, descriptors, permutation)
      call hash_descriptor_list(descriptors, permutation, local_hashes)

      allocate (gathered_hashes(2, nprocs))
      call MPI_Allgather(local_hashes, 2, MPI_INTEGER8, gathered_hashes, 2, MPI_INTEGER8, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      hashes_match = .true.
      do i = 2, nprocs
         if (any(gathered_hashes(:, i) /= gathered_hashes(:, 1))) then
            hashes_match = .false.
            exit
         end if
      end do

      if (.not. hashes_match) then
         ! Descriptor consistency is only meaningful after ranks have already
         ! agreed to enter the same communicator collective. Communicator
         ! disagreement across would-be participants is documented as unsupported.
         status = FTIMER_ERR_MPI_INCON
         return
      end if

      call MPI_Allreduce(local_summary%total_time, min_total_time, 1, MPI_DOUBLE_PRECISION, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_summary%total_time, max_total_time, 1, MPI_DOUBLE_PRECISION, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_summary%total_time, sum_total_time, 1, MPI_DOUBLE_PRECISION, MPI_SUM, active_comm, mpierr)
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
      allocate (sum_calls(entry_count))

      do i = 1, entry_count
         local_idx = permutation(i)
         local_inclusive(i) = local_summary%entries(local_idx)%inclusive_time
         local_self(i) = local_summary%entries(local_idx)%self_time
         local_calls(i) = local_summary%entries(local_idx)%call_count
         local_pct(i) = local_summary%entries(local_idx)%pct_time
      end do

      call MPI_Allreduce(local_inclusive, min_inclusive, entry_count, MPI_DOUBLE_PRECISION, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_inclusive, max_inclusive, entry_count, MPI_DOUBLE_PRECISION, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_inclusive, sum_inclusive, entry_count, MPI_DOUBLE_PRECISION, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_self, min_self, entry_count, MPI_DOUBLE_PRECISION, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_self, max_self, entry_count, MPI_DOUBLE_PRECISION, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_self, sum_self, entry_count, MPI_DOUBLE_PRECISION, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_pct, min_pct, entry_count, MPI_DOUBLE_PRECISION, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_pct, max_pct, entry_count, MPI_DOUBLE_PRECISION, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_pct, sum_pct, entry_count, MPI_DOUBLE_PRECISION, MPI_SUM, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_calls, min_calls, entry_count, MPI_INTEGER, MPI_MIN, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_calls, max_calls, entry_count, MPI_INTEGER, MPI_MAX, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         call clear_mpi_summary(summary)
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Allreduce(local_calls, sum_calls, entry_count, MPI_INTEGER, MPI_SUM, active_comm, mpierr)
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
      summary%total_time_imbalance = 1.0_wp
   end subroutine clear_mpi_summary

#ifdef FTIMER_USE_MPI
   subroutine build_descriptor_order(summary, descriptors, permutation)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: descriptors(:)
      integer, allocatable, intent(out) :: permutation(:)
      character(len=:), allocatable :: path_strings(:)
      character(len=FTIMER_NAME_LEN + 5) :: component
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
         component_len = descriptor_component_length(summary%entries(i)%name)
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
         call encode_descriptor_component(summary%entries(i)%name, component, component_len)
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

      component_len = 5 + len_trim(name)
   end function descriptor_component_length

   subroutine encode_descriptor_component(name, component, component_len)
      character(len=*), intent(in) :: name
      character(len=*), intent(out) :: component
      integer, intent(out) :: component_len
      character(len=4) :: len_text
      integer :: trimmed_len

      component = ''
      trimmed_len = len_trim(name)
      component_len = descriptor_component_length(name)

      write (len_text, '(i4.4)') trimmed_len
      component(1:component_len) = len_text//':'//name(1:trimmed_len)
   end subroutine encode_descriptor_component

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
            high_hash = hash_step(high_hash, int(iachar(descriptors(permutation(i))(j:j)), int64), &
                                  16777619_int64, 4294967291_int64)
            low_hash = hash_step(low_hash, int(iachar(descriptors(permutation(i))(j:j)), int64), &
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
