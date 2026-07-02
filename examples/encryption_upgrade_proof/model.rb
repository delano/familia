# examples/encryption_upgrade_proof/model.rb
#
# frozen_string_literal: true

# Field-level proof models. No database connection is required: the proof
# exercises encryption through the field setter/getter (ConcealedString)
# without ever calling save.

module ProofApp
  # Mirrors the shape of Onetime::Secret: a single encrypted field with no
  # aad_fields and no key_material, identified by an objid assigned at
  # creation time.
  class Secret < Familia::Horreum
    feature :encrypted_fields

    identifier_field :objid
    field :objid
    field :owner_id
    encrypted_field :ciphertext
  end

  # Exercises the aad_fields code path (SHA-256 digest AAD binding extra
  # field values), which Onetime::Secret does not use today.
  class Document < Familia::Horreum
    feature :encrypted_fields

    identifier_field :docid
    field :docid
    field :owner_id
    encrypted_field :content, aad_fields: [:owner_id]
  end
end
