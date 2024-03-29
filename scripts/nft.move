module nft_address::first_aptos_nft{
    use std::option;
    use std::option::{none, Option};
    use std::signer;
    use aptos_token_objects::collection;
    use std::string::{Self,String, utf8};
    use aptos_std::string_utils;
    use aptos_framework::account::{Self,SignerCapability};
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_framework::timestamp;
    use aptos_token_objects::royalty;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token::{royalty, Token, uri};
    use aptos_token_objects::token;

    // ERROR CODE
    const ERROR_NOWNER: u64 = 1;

    const ResourceAccountSeed: vector<u8> = b"mfers";

    const CollectionDescription: vector<u8> = b"mfers are generated entirely from hand drawings by sartoshi. this project is in the public domain; feel free to use mfers any way you want.";

    const CollectionName: vector<u8> = b"mfers";

    const CollectionURI: vector<u8> = b"ipfs://QmWmgfYhDWjzVheQyV2TnpVXYnKR25oLWCB2i9JeBxsJbz";

    const TokenURI: vector<u8> = b"ipfs://bafybeiearr64ic2e7z5ypgdpu2waasqdrslhzjjm65hrsui2scqanau3ya/";

    const TokenPrefix: vector<u8> = b"mfer #";

    struct ResourceCap has key {
        cap: SignerCapability
    }

    struct CollectionRefsStore has key {
        mutator_ref: collection::MutatorRef
    }

    struct TokenRefsStore has key {
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
        extend_ref: object::ExtendRef,
        transfer_ref: option::Option<object::TransferRef>
    }

    struct Content has key {
        content: string::String
    }

    #[event]
    struct MintEvent has drop, store {
        owner: address,
        token_id: address,
        content: string::String
    }

    #[event]
    struct SetContentEvent has drop,store {
        owner: address,
        token_id: address,  //event will broadcast the address of the object
        old_content: string::String,
        new_content: string::String
    }

    #[event]
    struct BurnEvent has drop, store {
        owner: address,
        token_id: address,
        content: string::String
    }

    // when a module is being published for the first time, and not during an upgrade, will the VM search for and execute an init_module(account: &signer) function
    fun init_module(sender: &signer){

        let (resource_signer, resource_cap) = account::create_resource_account(
            sender,
            ResourceAccountSeed
        );

        move_to(
          &resource_signer,
            ResourceCap{
                cap: resource_cap
            }
        );

        let collection_cref = collection::create_unlimited_collection(
            &resource_signer,
            string::utf8(CollectionDescription),
            string::utf8(CollectionName),
            option::some(royalty::create(5,100,signer::address_of(sender))), // if you want to get the address of a signer, use signer::address_of()
            string::utf8(CollectionURI)
        );

        // collection_cref is an object, if you want to operate on object, you can do this with its address
        let collection_signer = object::generate_signer(&collection_cref);

        // The object address has been stored inside mutator ref which provides the method to modify description and uri
        let mutator_ref = collection::generate_mutator_ref(&collection_cref);

        move_to(
            &collection_signer,
            CollectionRefsStore{
                mutator_ref
            }
        );
    }

    public entry fun mint(
        sender: &signer,
        content: string::String
    ) acquires ResourceCap {
        let resource_cap = &borrow_global<ResourceCap>(
            account::create_resource_address(
                &@nft_address,
                ResourceAccountSeed
            )
        ).cap;

        let resource_signer = &account::create_signer_with_capability(
            resource_cap
        );

        let url = string::utf8(TokenURI);

        let token_cref = token::create_numbered_token(
            resource_signer,
            string::utf8(CollectionName),
            string::utf8(CollectionDescription),
            string::utf8(TokenPrefix),
            string::utf8(b""),
            option::none(),
            string::utf8(b"")
        );

        let id = token::index<Token>(object::object_from_constructor_ref(&token_cref));
        string::append(&mut url, string_utils::to_string(&id));
        string::append(&mut url, string::utf8(b".png"));

        let token_signer= object::generate_signer(&token_cref);

        // create token_mutator_ref
        let token_mutator_ref = token::generate_mutator_ref(&token_cref);

        token::set_uri(&token_mutator_ref,url);

        // create generate_burn_ref
        let token_burn_ref = token::generate_burn_ref(&token_cref);

        move_to(
            &token_signer,
            TokenRefsStore{
                mutator_ref: token_mutator_ref,
                burn_ref: token_burn_ref,
                extend_ref: object::generate_extend_ref(&token_cref),
                transfer_ref: option::none()
            }
        );

        move_to(
            &token_signer,
            Content{
                content
            }
        );

        event::emit(
            MintEvent{
                owner: signer::address_of(sender),
                token_id: object::address_from_constructor_ref(&token_cref),
                content
            }
        );

        // First the resource account create the NFT, and then transfer to caller address
        object::transfer(
            resource_signer,
            object::object_from_constructor_ref<Token>(&token_cref),
            signer::address_of(sender)
        )

    }

    entry fun burn(
        sender: &signer,
        object: Object<Content>
    ) acquires TokenRefsStore, Content {
        assert!(object::is_owner(object,signer::address_of(sender)),ERROR_NOWNER);
        let TokenRefsStore{
            mutator_ref: _,
            burn_ref,
            extend_ref: _,
            transfer_ref: _
        } = move_from<TokenRefsStore>(object::object_address(&object));

        let Content {
            content
        } = move_from<Content>(object::object_address(&object));

        event::emit(
            BurnEvent {
                owner: object::owner(object),
                token_id: object::object_address(&object),
                content
            }
        );

        token::burn(burn_ref);
    }

    entry fun set_content(
        sender: &signer,
        object: Object<Content>,
        content: string::String
    ) acquires  Content {
        let old_content = borrow_content(signer::address_of(sender),object).content;
        event::emit(
            SetContentEvent {
                owner: object::owner(object),
                token_id: object::object_address(&object),
                old_content,
                new_content: content
            }
        );
        borrow_mut_content(signer::address_of(sender), object).content = content;
    }

    inline fun borrow_content(owner: address, object: Object<Content>): &Content {
        assert!(object::is_owner(object, owner), ERROR_NOWNER);
        borrow_global<Content>(object::object_address(&object))
    }

    inline fun borrow_mut_content(owner: address, object: Object<Content>): &mut Content {
        assert!(object::is_owner(object, owner), ERROR_NOWNER);
        borrow_global_mut<Content>(object::object_address(&object))
    }

    #[view]
    public fun get_content(object: Object<Content>): string::String acquires Content {
        borrow_global<Content>(object::object_address(&object)).content
    }

    #[test_only]
    public fun init_for_test(sender: &signer) {
        init_module(sender)
    }

}