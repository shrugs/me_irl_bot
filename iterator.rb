class Iterator
  def initialize(arr)
    @arr = arr
    @i = 0
  end

  def next
    r = @arr[@i]
    @i = (@i + 1) % @arr.length
    return r
  end
end