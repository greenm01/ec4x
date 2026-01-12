import ../core/sam
import ../model/state

proc defaultAcceptor*(model: var ClientModel, proposal: Proposal[ClientModel]): bool =
  ## The default acceptor simply executes the payload
  ## In complex SAM, you might have specific acceptors for specific proposal types
  ## that validate or partially accept.
  
  # Execute the mutation
  proposal.payload(model)
  return true
