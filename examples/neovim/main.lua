vim.fn.fnamemodify(vim.fs.joinpath("foo", "bar"), ":p") -- This line passes
vim.fn.fnamemodify(vim.fs.joinpath(123, "bad"), ":p") -- This line fails
