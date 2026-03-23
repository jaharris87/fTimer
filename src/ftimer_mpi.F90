module ftimer_mpi
   use, intrinsic :: iso_fortran_env, only: int64
   use ftimer_types, only: FTIMER_ERR_MPI_INCON, FTIMER_ERR_UNKNOWN, FTIMER_NAME_LEN, FTIMER_SUCCESS, &
                           ftimer_summary_t, wp
#ifdef FTIMER_USE_MPI
   use mpi
#endif
   implicit none
   private

   public :: augment_summary_with_mpi
   public :: ftimer_mpi_enabled

contains

   logical function ftimer_mpi_enabled()
#ifdef FTIMER_USE_MPI
      ftimer_mpi_enabled = .true.
#else
      ftimer_mpi_enabled = .false.
#endif
   end function ftimer_mpi_enabled

   subroutine augment_summary_with_mpi(summary, comm, status)
      type(ftimer_summary_t), intent(inout) :: summary
      integer, intent(in) :: comm
      integer, intent(out) :: status
#ifdef FTIMER_USE_MPI
      integer :: active_comm
      integer :: entry_count
      integer :: i
      integer :: idx
      integer :: mpierr
      integer :: nprocs
      integer :: rank
      integer, allocatable :: permutation(:)
      integer(int64) :: local_hash
      integer(int64), allocatable :: gathered_hashes(:)
      real(wp), allocatable :: send_values(:)
      real(wp), allocatable :: min_values(:)
      real(wp), allocatable :: max_values(:)
      real(wp), allocatable :: sum_values(:)
      character(len=:), allocatable :: descriptors(:)

      status = FTIMER_SUCCESS
      summary%has_mpi_data = .false.

      active_comm = comm
      if (active_comm < 0) active_comm = MPI_COMM_WORLD

      call MPI_Comm_rank(active_comm, rank, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Comm_size(active_comm, nprocs, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call build_descriptor_order(summary, descriptors, permutation)
      local_hash = hash_descriptor_list(descriptors, permutation)

      allocate (gathered_hashes(nprocs))
      call MPI_Allgather(local_hash, 1, MPI_INTEGER8, gathered_hashes, 1, MPI_INTEGER8, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      if (.not. all(gathered_hashes == gathered_hashes(1))) then
         status = FTIMER_ERR_MPI_INCON
         return
      end if

      entry_count = summary%num_entries
      if (entry_count <= 0) return

      allocate (send_values(entry_count))
      allocate (min_values(entry_count))
      allocate (max_values(entry_count))
      allocate (sum_values(entry_count))

      do i = 1, entry_count
         send_values(i) = summary%entries(permutation(i))%inclusive_time
      end do

      call MPI_Reduce(send_values, min_values, entry_count, MPI_DOUBLE_PRECISION, MPI_MIN, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Reduce(send_values, max_values, entry_count, MPI_DOUBLE_PRECISION, MPI_MAX, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      call MPI_Reduce(send_values, sum_values, entry_count, MPI_DOUBLE_PRECISION, MPI_SUM, 0, active_comm, mpierr)
      if (mpierr /= MPI_SUCCESS) then
         status = FTIMER_ERR_UNKNOWN
         return
      end if

      if (rank /= 0) return

      do i = 1, entry_count
         idx = permutation(i)
         summary%entries(idx)%min_time = min_values(i)
         summary%entries(idx)%max_time = max_values(i)
         summary%entries(idx)%avg_across_ranks = sum_values(i)/real(nprocs, wp)
         summary%entries(idx)%imbalance = compute_imbalance(max_values(i), summary%entries(idx)%avg_across_ranks)
      end do
      summary%has_mpi_data = .true.
#else
      status = FTIMER_SUCCESS
      summary%has_mpi_data = .false.
#endif
   end subroutine augment_summary_with_mpi

#ifdef FTIMER_USE_MPI
   subroutine build_descriptor_order(summary, descriptors, permutation)
      type(ftimer_summary_t), intent(in) :: summary
      character(len=:), allocatable, intent(out) :: descriptors(:)
      integer, allocatable, intent(out) :: permutation(:)
      character(len=:), allocatable :: path_strings(:)
      character(len=FTIMER_NAME_LEN + 5) :: component
      integer, allocatable :: prefix_lengths(:)
      integer :: component_len
      integer :: depth
      integer :: i
      integer :: max_depth
      integer :: max_len

      if (summary%num_entries <= 0) then
         allocate (character(len=1) :: descriptors(0))
         allocate (permutation(0))
         return
      end if

      max_depth = 0
      do i = 1, summary%num_entries
         max_depth = max(max_depth, summary%entries(i)%depth)
      end do

      allocate (prefix_lengths(max_depth + 1))
      prefix_lengths = 0
      max_len = 1

      do i = 1, summary%num_entries
         depth = summary%entries(i)%depth
         component_len = descriptor_component_length(summary%entries(i)%name)
         if (depth == 0) then
            prefix_lengths(1) = component_len
         else
            prefix_lengths(depth + 1) = prefix_lengths(depth) + component_len
         end if
         max_len = max(max_len, prefix_lengths(depth + 1))
      end do

      allocate (character(len=max_len) :: descriptors(summary%num_entries))
      allocate (character(len=max_len) :: path_strings(max_depth + 1))
      allocate (permutation(summary%num_entries))

      descriptors = ''
      path_strings = ''

      do i = 1, summary%num_entries
         depth = summary%entries(i)%depth
         call encode_descriptor_component(summary%entries(i)%name, component, component_len)
         if (depth == 0) then
            path_strings(1) = component(1:component_len)
         else
            path_strings(depth + 1) = trim(path_strings(depth))//component(1:component_len)
         end if
         descriptors(i) = path_strings(depth + 1)
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

   integer(int64) function hash_descriptor_list(descriptors, permutation) result(hash_value)
      character(len=*), intent(in) :: descriptors(:)
      integer, intent(in) :: permutation(:)
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

      hash_value = ishft(high_hash, 32) + low_hash
   end function hash_descriptor_list

   integer(int64) function hash_step(current, value, base, modulus) result(updated)
      integer(int64), intent(in) :: current
      integer(int64), intent(in) :: value
      integer(int64), intent(in) :: base
      integer(int64), intent(in) :: modulus

      updated = modulo(current*base + value, modulus)
   end function hash_step

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
#endif

end module ftimer_mpi
