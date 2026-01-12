-- Tests for encryption.lua: command construction

local encryption = require("resurrect.encryption")
local captured_calls = {}

describe("Encryption", function()
	before(function()
		captured_calls = {}
		encryption.enable = false
		encryption.method = "age"
		encryption.private_key = nil
		encryption.public_key = nil

		wezterm.run_child_process = function(args)
			captured_calls[#captured_calls + 1] = { type = "run_child_process", args = args }
			return true, "decrypted content", ""
		end
	end)

	describe("decrypt", function()
		it("constructs age decrypt command correctly", function()
			encryption.method = "age"
			encryption.private_key = "/keys/age.key"
			encryption.decrypt("/state/workspace.json")

			expect(#captured_calls).to.equal(1)
			local cmd = captured_calls[1].args
			expect(cmd[1]).to.equal("age")
			expect(cmd[2]).to.equal("-d")
			expect(cmd[3]).to.equal("-i")
			expect(cmd[4]).to.equal("/keys/age.key")
			expect(cmd[5]).to.equal("/state/workspace.json")
		end)

		it("constructs gpg decrypt command correctly", function()
			encryption.method = "gpg"
			encryption.decrypt("/state/workspace.json")

			local cmd = captured_calls[1].args
			expect(cmd[1]).to.equal("gpg")
			expect(cmd[2]).to.equal("--batch")
			expect(cmd[3]).to.equal("--yes")
			expect(cmd[4]).to.equal("--decrypt")
			expect(cmd[5]).to.equal("/state/workspace.json")
		end)
	end)
end)
